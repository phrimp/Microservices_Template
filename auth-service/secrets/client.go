package secrets

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"sync"
	"time"

	consul "github.com/hashicorp/consul/api"
	vault "github.com/hashicorp/vault/api"
)

// SecretMetadata stores information about a secret
type SecretMetadata struct {
	Name        string   `json:"name"`
	Type        string   `json:"type"`
	Path        string   `json:"path"`
	CreatedAt   string   `json:"created_at"`
	RotationDue string   `json:"rotation_due"`
	Owner       string   `json:"owner"`
	Consumers   []string `json:"consumers"`
	// Type-specific fields
	KeyID     string `json:"key_id,omitempty"`
	Algorithm string `json:"algorithm,omitempty"`
	Provider  string `json:"provider,omitempty"`
	Service   string `json:"service,omitempty"`
}

// DynamicSecretsClient provides functionality to access secrets dynamically
type DynamicSecretsClient struct {
	vaultClient   *vault.Client
	consulClient  *consul.Client
	serviceID     string
	secretsCache  map[string]interface{}
	metadataCache map[string]SecretMetadata
	cacheMutex    sync.RWMutex
	refreshTicker *time.Ticker
}

// NewDynamicSecretsClient creates a new client for accessing secrets
func NewDynamicSecretsClient(vaultAddr, consulAddr, serviceID, roleID, secretID string) (*DynamicSecretsClient, error) {
	// Create Vault client
	vaultConfig := vault.DefaultConfig()
	vaultConfig.Address = vaultAddr

	vaultClient, err := vault.NewClient(vaultConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to create vault client: %w", err)
	}

	// Create Consul client
	consulConfig := consul.DefaultConfig()
	consulConfig.Address = consulAddr

	consulClient, err := consul.NewClient(consulConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to create consul client: %w", err)
	}

	client := &DynamicSecretsClient{
		vaultClient:   vaultClient,
		consulClient:  consulClient,
		serviceID:     serviceID,
		secretsCache:  make(map[string]interface{}),
		metadataCache: make(map[string]SecretMetadata),
		refreshTicker: time.NewTicker(5 * time.Minute), // Refresh cache every 5 minutes
	}

	// Authenticate to Vault
	if err := client.authenticateWithAppRole(roleID, secretID); err != nil {
		return nil, fmt.Errorf("vault authentication failed: %w", err)
	}

	// Start the background cache refresh
	go client.backgroundRefresh()

	// Initial load of secrets
	if err := client.refreshSecrets(); err != nil {
		log.Printf("WARNING: Initial secret load failed: %v", err)
	}

	return client, nil
}

// authenticateWithAppRole authenticates to Vault using AppRole
func (c *DynamicSecretsClient) authenticateWithAppRole(roleID, secretID string) error {
	data := map[string]interface{}{
		"role_id":   roleID,
		"secret_id": secretID,
	}

	resp, err := c.vaultClient.Logical().Write("auth/approle/login", data)
	if err != nil {
		return fmt.Errorf("failed to authenticate with approle: %w", err)
	}

	// Set the token for future requests
	c.vaultClient.SetToken(resp.Auth.ClientToken)

	// Set up token renewal if needed
	if resp.Auth.Renewable && resp.Auth.LeaseDuration > 0 {
		go c.renewToken(resp.Auth.ClientToken, resp.Auth.LeaseDuration)
	}

	return nil
}

// renewToken periodically renews the Vault token
func (c *DynamicSecretsClient) renewToken(token string, leaseDuration int) {
	// Renew at 2/3 of the lease duration
	renewInterval := time.Duration(float64(leaseDuration) * 2 / 3 * float64(time.Second))

	for {
		time.Sleep(renewInterval)

		// Try to renew the token
		_, err := c.vaultClient.Auth().Token().RenewSelf(leaseDuration)
		if err != nil {
			log.Printf("WARNING: Failed to renew token: %v", err)
			return
		}
	}
}

// backgroundRefresh periodically refreshes the secrets cache
func (c *DynamicSecretsClient) backgroundRefresh() {
	for range c.refreshTicker.C {
		if err := c.refreshSecrets(); err != nil {
			log.Printf("WARNING: Failed to refresh secrets: %v", err)
		}
	}
}

// refreshSecrets updates the cache with the latest secrets
func (c *DynamicSecretsClient) refreshSecrets() error {
	// Get the list of secrets this service has access to
	secretsMetadata, err := c.getServiceSecrets()
	if err != nil {
		return fmt.Errorf("failed to get service secrets: %w", err)
	}

	// Lock for writing to the cache
	c.cacheMutex.Lock()
	defer c.cacheMutex.Unlock()

	// Clear old cache
	c.metadataCache = make(map[string]SecretMetadata)

	// Update metadata cache and fetch secret values
	for _, metadata := range secretsMetadata {
		cacheKey := fmt.Sprintf("%s/%s", metadata.Type, strings.Split(metadata.Path, "/")[2])
		c.metadataCache[cacheKey] = metadata

		// Fetch the actual secret
		secret, err := c.fetchSecret(metadata.Path)
		if err != nil {
			log.Printf("WARNING: Failed to fetch secret %s: %v", metadata.Path, err)
			continue
		}

		c.secretsCache[cacheKey] = secret
	}

	return nil
}

// getServiceSecrets retrieves metadata for all secrets accessible by this service
func (c *DynamicSecretsClient) getServiceSecrets() ([]SecretMetadata, error) {
	// Get all secret types from Consul
	pairs, _, err := c.consulClient.KV().List("secret-metadata/", nil)
	if err != nil {
		return nil, fmt.Errorf("failed to list secret metadata: %w", err)
	}

	var accessibleSecrets []SecretMetadata
	for _, pair := range pairs {
		// Skip the root folder
		if strings.Count(pair.Key, "/") < 1 {
			continue
		}

		var metadata SecretMetadata
		if err := json.Unmarshal(pair.Value, &metadata); err != nil {
			log.Printf("WARNING: Failed to unmarshal metadata for %s: %v", pair.Key, err)
			continue
		}

		// Check if this service is a consumer
		isConsumer := false
		for _, consumer := range metadata.Consumers {
			if consumer == c.serviceID {
				isConsumer = true
				break
			}
		}

		if isConsumer {
			accessibleSecrets = append(accessibleSecrets, metadata)
		}
	}

	return accessibleSecrets, nil
}

// fetchSecret retrieves a secret from Vault
func (c *DynamicSecretsClient) fetchSecret(path string) (map[string]interface{}, error) {
	// Parse the path
	pathParts := strings.Split(path, "/")
	if len(pathParts) < 3 {
		return nil, fmt.Errorf("invalid path format: %s", path)
	}

	engine := pathParts[0]
	secretPath := strings.Join(pathParts[1:], "/")

	// Get the secret from Vault
	secret, err := c.vaultClient.KVv2(engine).Get(context.Background(), secretPath)
	if err != nil {
		return nil, fmt.Errorf("failed to get secret from vault: %w", err)
	}

	return secret.Data, nil
}

// GetSecret retrieves a secret by type and ID
func (c *DynamicSecretsClient) GetSecret(secretType, secretID string) (map[string]interface{}, error) {
	cacheKey := fmt.Sprintf("%s/%s", secretType, secretID)

	// Try to get from cache first
	c.cacheMutex.RLock()
	secret, exists := c.secretsCache[cacheKey]
	c.cacheMutex.RUnlock()

	if exists {
		return secret.(map[string]interface{}), nil
	}

	// If not in cache, try to fetch directly
	metadata, err := c.GetSecretMetadata(secretType, secretID)
	if err != nil {
		return nil, fmt.Errorf("failed to get secret metadata: %w", err)
	}

	secret, err = c.fetchSecret(metadata.Path)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch secret: %w", err)
	}

	// Update cache
	c.cacheMutex.Lock()
	c.secretsCache[cacheKey] = secret
	c.cacheMutex.Unlock()

	return secret.(map[string]interface{}), nil
}

// GetJWTKey retrieves a JWT key by ID
func (c *DynamicSecretsClient) GetJWTKey(keyID string) (privateKey, publicKey, algorithm string, err error) {
	data, err := c.GetSecret("jwt", keyID)
	if err != nil {
		return "", "", "", fmt.Errorf("failed to get JWT key: %w", err)
	}

	privateKey, ok := data["private_key"].(string)
	if !ok {
		return "", "", "", fmt.Errorf("missing private_key in JWT secret")
	}

	publicKey, ok = data["public_key"].(string)
	if !ok {
		return "", "", "", fmt.Errorf("missing public_key in JWT secret")
	}

	algorithm, ok = data["algorithm"].(string)
	if !ok {
		return "", "", "", fmt.Errorf("missing algorithm in JWT secret")
	}

	return privateKey, publicKey, algorithm, nil
}

// GetOAuthCredentials retrieves OAuth credentials by provider
func (c *DynamicSecretsClient) GetOAuthCredentials(provider string) (clientID, clientSecret, redirectURI string, err error) {
	data, err := c.GetSecret("oauth", provider)
	if err != nil {
		return "", "", "", fmt.Errorf("failed to get OAuth credentials: %w", err)
	}

	clientID, ok := data["client_id"].(string)
	if !ok {
		return "", "", "", fmt.Errorf("missing client_id in OAuth secret")
	}

	clientSecret, ok = data["client_secret"].(string)
	if !ok {
		return "", "", "", fmt.Errorf("missing client_secret in OAuth secret")
	}

	redirectURI, ok = data["redirect_uri"].(string)
	if !ok {
		redirectURI = "" // Not required
	}

	return clientID, clientSecret, redirectURI, nil
}

// GetAPIKey retrieves an API key by service
func (c *DynamicSecretsClient) GetAPIKey(service string) (key, apiURL string, err error) {
	data, err := c.GetSecret("api-key", service)
	if err != nil {
		return "", "", fmt.Errorf("failed to get API key: %w", err)
	}

	key, ok := data["key"].(string)
	if !ok {
		return "", "", fmt.Errorf("missing key in API key secret")
	}

	apiURL, ok = data["api_url"].(string)
	if !ok {
		apiURL = "" // Not required
	}

	return key, apiURL, nil
}

// GetSecretMetadata retrieves metadata for a secret
func (c *DynamicSecretsClient) GetSecretMetadata(secretType, secretID string) (SecretMetadata, error) {
	cacheKey := fmt.Sprintf("%s/%s", secretType, secretID)

	// Try to get from cache first
	c.cacheMutex.RLock()
	metadata, exists := c.metadataCache[cacheKey]
	c.cacheMutex.RUnlock()

	if exists {
		return metadata, nil
	}

	// If not in cache, fetch from Consul
	pair, _, err := c.consulClient.KV().Get(fmt.Sprintf("secret-metadata/%s/%s", secretType, secretID), nil)
	if err != nil {
		return SecretMetadata{}, fmt.Errorf("failed to get secret metadata: %w", err)
	}

	if pair == nil {
		return SecretMetadata{}, fmt.Errorf("secret metadata not found for %s/%s", secretType, secretID)
	}

	if err := json.Unmarshal(pair.Value, &metadata); err != nil {
		return SecretMetadata{}, fmt.Errorf("failed to unmarshal secret metadata: %w", err)
	}

	// Update cache
	c.cacheMutex.Lock()
	c.metadataCache[cacheKey] = metadata
	c.cacheMutex.Unlock()

	return metadata, nil
}

// ListSecretsByType retrieves all secrets of a specific type accessible by this service
func (c *DynamicSecretsClient) ListSecretsByType(secretType string) ([]SecretMetadata, error) {
	c.cacheMutex.RLock()
	defer c.cacheMutex.RUnlock()

	var result []SecretMetadata
	for key, metadata := range c.metadataCache {
		if strings.HasPrefix(key, secretType+"/") {
			result = append(result, metadata)
		}
	}

	return result, nil
}

// Close stops the background refreshing
func (c *DynamicSecretsClient) Close() {
	if c.refreshTicker != nil {
		c.refreshTicker.Stop()
	}
}
