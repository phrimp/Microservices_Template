package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	consul "github.com/hashicorp/consul/api"
	vault "github.com/hashicorp/vault/api"
)

// Secret types and schemas
type SecretType struct {
	Name           string   `json:"name"`
	Format         string   `json:"format"`
	Fields         []string `json:"fields"`
	RotationPeriod string   `json:"rotation_period"`
}

// Secret metadata
type SecretMetadata struct {
	Name        string   `json:"name"`
	Type        string   `json:"type"`
	Path        string   `json:"path"`
	CreatedAt   string   `json:"created_at"`
	RotationDue string   `json:"rotation_due"`
	Owner       string   `json:"owner"`
	Consumers   []string `json:"consumers"`
	// Type-specific fields can be added
	KeyID     string `json:"key_id,omitempty"`
	Algorithm string `json:"algorithm,omitempty"`
	Provider  string `json:"provider,omitempty"`
	Service   string `json:"service,omitempty"`
}

// Secret creation request
type CreateSecretRequest struct {
	Name           string                 `json:"name"`
	Type           string                 `json:"type"`
	Data           map[string]interface{} `json:"data"`
	Owner          string                 `json:"owner"`
	Consumers      []string               `json:"consumers"`
	CustomMetadata map[string]interface{} `json:"custom_metadata,omitempty"`
}

// Service registration
type ServiceSecretAccess struct {
	Description string   `json:"description"`
	SecretTypes []string `json:"secret_types"`
}

// VaultClient wraps vault operations
type VaultClient struct {
	client *vault.Client
}

// ConsulClient wraps consul operations
type ConsulClient struct {
	client *consul.Client
}

// SecretManagementAPI combines vault and consul clients
type SecretManagementAPI struct {
	vaultClient  *VaultClient
	consulClient *ConsulClient
}

// NewVaultClient creates a new vault client
func NewVaultClient(address string) (*VaultClient, error) {
	config := vault.DefaultConfig()
	config.Address = address

	client, err := vault.NewClient(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create vault client: %w", err)
	}

	return &VaultClient{client: client}, nil
}

// NewConsulClient creates a new consul client
func NewConsulClient(address string) (*ConsulClient, error) {
	config := consul.DefaultConfig()
	config.Address = address

	client, err := consul.NewClient(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create consul client: %w", err)
	}

	return &ConsulClient{client: client}, nil
}

// AuthenticateWithAppRole authenticates to Vault using AppRole
func (vc *VaultClient) AuthenticateWithAppRole(roleID, secretID string) error {
	data := map[string]interface{}{
		"role_id":   roleID,
		"secret_id": secretID,
	}

	resp, err := vc.client.Logical().Write("auth/approle/login", data)
	if err != nil {
		return fmt.Errorf("failed to authenticate with approle: %w", err)
	}

	// Set the token for future requests
	vc.client.SetToken(resp.Auth.ClientToken)
	return nil
}

// GetSecretTypes retrieves all registered secret types from Consul
func (cc *ConsulClient) GetSecretTypes() (map[string]SecretType, error) {
	pairs, _, err := cc.client.KV().List("secret-types/", nil)
	if err != nil {
		return nil, fmt.Errorf("failed to list secret types: %w", err)
	}

	types := make(map[string]SecretType)
	for _, pair := range pairs {
		key := strings.TrimPrefix(pair.Key, "secret-types/")
		if key == "" {
			continue
		}

		var secretType SecretType
		if err := json.Unmarshal(pair.Value, &secretType); err != nil {
			return nil, fmt.Errorf("failed to unmarshal secret type %s: %w", key, err)
		}

		types[key] = secretType
	}

	return types, nil
}

// GetSecretType retrieves a specific secret type from Consul
func (cc *ConsulClient) GetSecretType(typeID string) (*SecretType, error) {
	pair, _, err := cc.client.KV().Get(fmt.Sprintf("secret-types/%s", typeID), nil)
	if err != nil {
		return nil, fmt.Errorf("failed to get secret type: %w", err)
	}

	if pair == nil {
		return nil, fmt.Errorf("secret type %s not found", typeID)
	}

	var secretType SecretType
	if err := json.Unmarshal(pair.Value, &secretType); err != nil {
		return nil, fmt.Errorf("failed to unmarshal secret type: %w", err)
	}

	return &secretType, nil
}

// GetSecretMetadata retrieves metadata for a secret from Consul
func (cc *ConsulClient) GetSecretMetadata(typeID, secretID string) (*SecretMetadata, error) {
	pair, _, err := cc.client.KV().Get(fmt.Sprintf("secret-metadata/%s/%s", typeID, secretID), nil)
	if err != nil {
		return nil, fmt.Errorf("failed to get secret metadata: %w", err)
	}

	if pair == nil {
		return nil, fmt.Errorf("secret metadata for %s/%s not found", typeID, secretID)
	}

	var metadata SecretMetadata
	if err := json.Unmarshal(pair.Value, &metadata); err != nil {
		return nil, fmt.Errorf("failed to unmarshal secret metadata: %w", err)
	}

	return &metadata, nil
}

// ListSecrets retrieves all secret metadata of a specific type
func (cc *ConsulClient) ListSecrets(typeID string) ([]SecretMetadata, error) {
	pairs, _, err := cc.client.KV().List(fmt.Sprintf("secret-metadata/%s/", typeID), nil)
	if err != nil {
		return nil, fmt.Errorf("failed to list secrets: %w", err)
	}

	var secrets []SecretMetadata
	for _, pair := range pairs {
		key := strings.TrimPrefix(pair.Key, fmt.Sprintf("secret-metadata/%s/", typeID))
		if key == "" {
			continue
		}

		var metadata SecretMetadata
		if err := json.Unmarshal(pair.Value, &metadata); err != nil {
			log.Printf("Warning: failed to unmarshal secret metadata %s: %v", pair.Key, err)
			continue
		}

		secrets = append(secrets, metadata)
	}

	return secrets, nil
}

// StoreSecret stores a secret in Vault and its metadata in Consul
func (api *SecretManagementAPI) StoreSecret(req CreateSecretRequest) error {
	// Validate the secret type
	secretType, err := api.consulClient.GetSecretType(req.Type)
	if err != nil {
		return fmt.Errorf("invalid secret type: %w", err)
	}

	// Validate required fields
	for _, field := range secretType.Fields {
		if _, ok := req.Data[field]; !ok {
			return fmt.Errorf("missing required field: %s", field)
		}
	}

	// Generate a path for the secret
	secretID := req.Owner
	if customID, ok := req.CustomMetadata["id"].(string); ok && customID != "" {
		secretID = customID
	}

	path := fmt.Sprintf("dynamic-secrets/%s/%s", req.Type, secretID)

	// Calculate rotation due date based on type's rotation period
	now := time.Now().UTC()
	rotationDue := now
	switch secretType.RotationPeriod {
	case "30d":
		rotationDue = now.AddDate(0, 1, 0)
	case "90d":
		rotationDue = now.AddDate(0, 3, 0)
	case "180d":
		rotationDue = now.AddDate(0, 6, 0)
	case "365d":
		rotationDue = now.AddDate(1, 0, 0)
	default:
		rotationDue = now.AddDate(0, 3, 0) // Default to 90 days
	}

	// Add timestamps to the data
	data := make(map[string]interface{})
	for k, v := range req.Data {
		data[k] = v
	}
	data["created_at"] = now.Format(time.RFC3339)
	data["rotation_due"] = rotationDue.Format(time.RFC3339)

	// Store the secret in Vault
	_, err = api.vaultClient.client.KVv2("dynamic-secrets").Put(context.Background(), fmt.Sprintf("%s/%s", req.Type, secretID), data)
	if err != nil {
		return fmt.Errorf("failed to store secret in Vault: %w", err)
	}

	// Create metadata for Consul
	metadata := SecretMetadata{
		Name:        req.Name,
		Type:        req.Type,
		Path:        path,
		CreatedAt:   now.Format(time.RFC3339),
		RotationDue: rotationDue.Format(time.RFC3339),
		Owner:       req.Owner,
		Consumers:   req.Consumers,
	}

	// Add type-specific metadata
	if req.Type == "jwt" {
		if keyID, ok := req.Data["key_id"].(string); ok {
			metadata.KeyID = keyID
		}
		if algorithm, ok := req.Data["algorithm"].(string); ok {
			metadata.Algorithm = algorithm
		}
	} else if req.Type == "oauth" {
		if provider, ok := req.CustomMetadata["provider"].(string); ok {
			metadata.Provider = provider
		}
	} else if req.Type == "api-key" {
		if service, ok := req.CustomMetadata["service"].(string); ok {
			metadata.Service = service
		}
	}

	// Convert metadata to JSON
	metadataJSON, err := json.Marshal(metadata)
	if err != nil {
		return fmt.Errorf("failed to marshal secret metadata: %w", err)
	}

	// Store metadata in Consul
	_, err = api.consulClient.client.KV().Put(&consul.KVPair{
		Key:   fmt.Sprintf("secret-metadata/%s/%s", req.Type, secretID),
		Value: metadataJSON,
	}, nil)
	if err != nil {
		return fmt.Errorf("failed to store secret metadata in Consul: %w", err)
	}

	// Create or update the policy for this secret
	policyName := fmt.Sprintf("%s-%s", req.Type, secretID)
	policyHCL := fmt.Sprintf(`path "%s/data/%s/%s" {
  capabilities = ["read"]
}`, "dynamic-secrets", req.Type, secretID)

	err = api.vaultClient.client.Sys().PutPolicy(policyName, policyHCL)
	if err != nil {
		return fmt.Errorf("failed to create policy: %w", err)
	}

	// Update policies for consumer services
	for _, consumer := range req.Consumers {
		// Get current policies for the consumer
		roleResp, err := api.vaultClient.client.Logical().Read(fmt.Sprintf("auth/approle/role/%s", consumer))
		if err != nil {
			log.Printf("Warning: failed to read role for %s: %v", consumer, err)
			continue
		}

		if roleResp == nil {
			log.Printf("Warning: role %s not found", consumer)
			continue
		}

		// Extract current policies
		policies := roleResp.Data["token_policies"].([]interface{})
		policyStrings := make([]string, len(policies))
		for i, p := range policies {
			policyStrings[i] = p.(string)
		}

		// Add the new policy
		policyStrings = append(policyStrings, policyName)

		// Update the role with the new policy set
		_, err = api.vaultClient.client.Logical().Write(fmt.Sprintf("auth/approle/role/%s", consumer), map[string]interface{}{
			"token_policies": policyStrings,
		})
		if err != nil {
			log.Printf("Warning: failed to update policies for %s: %v", consumer, err)
		}
	}

	return nil
}

// DeleteSecret removes a secret from Vault and its metadata from Consul
func (api *SecretManagementAPI) DeleteSecret(typeID, secretID string) error {
	// Delete the secret from Vault
	err := api.vaultClient.client.KVv2("dynamic-secrets").Delete(context.Background(), fmt.Sprintf("%s/%s", typeID, secretID))
	if err != nil {
		return fmt.Errorf("failed to delete secret from Vault: %w", err)
	}

	// Delete the metadata from Consul
	_, err = api.consulClient.client.KV().Delete(fmt.Sprintf("secret-metadata/%s/%s", typeID, secretID), nil)
	if err != nil {
		return fmt.Errorf("failed to delete secret metadata from Consul: %w", err)
	}

	// Delete the policy
	policyName := fmt.Sprintf("%s-%s", typeID, secretID)
	err = api.vaultClient.client.Sys().DeletePolicy(policyName)
	if err != nil {
		log.Printf("Warning: failed to delete policy %s: %v", policyName, err)
	}

	return nil
}

// RotateSecret generates a new version of a secret
func (api *SecretManagementAPI) RotateSecret(typeID, secretID string, newData map[string]interface{}) error {
	// Get the current metadata
	metadata, err := api.consulClient.GetSecretMetadata(typeID, secretID)
	if err != nil {
		return fmt.Errorf("failed to get secret metadata: %w", err)
	}

	// Get the secret type
	secretType, err := api.consulClient.GetSecretType(typeID)
	if err != nil {
		return fmt.Errorf("invalid secret type: %w", err)
	}

	// Validate required fields
	for _, field := range secretType.Fields {
		if _, ok := newData[field]; !ok {
			return fmt.Errorf("missing required field for rotation: %s", field)
		}
	}

	// Calculate new rotation due date
	now := time.Now().UTC()
	rotationDue := now
	switch secretType.RotationPeriod {
	case "30d":
		rotationDue = now.AddDate(0, 1, 0)
	case "90d":
		rotationDue = now.AddDate(0, 3, 0)
	case "180d":
		rotationDue = now.AddDate(0, 6, 0)
	case "365d":
		rotationDue = now.AddDate(1, 0, 0)
	default:
		rotationDue = now.AddDate(0, 3, 0) // Default to 90 days
	}

	// Add timestamps to the data
	data := make(map[string]interface{})
	for k, v := range newData {
		data[k] = v
	}
	data["created_at"] = now.Format(time.RFC3339)
	data["rotation_due"] = rotationDue.Format(time.RFC3339)

	// Store the new secret version in Vault
	_, err = api.vaultClient.client.KVv2("dynamic-secrets").Put(context.Background(), fmt.Sprintf("%s/%s", typeID, secretID), data)
	if err != nil {
		return fmt.Errorf("failed to store rotated secret in Vault: %w", err)
	}

	// Update metadata
	metadata.RotationDue = rotationDue.Format(time.RFC3339)

	// Update type-specific metadata
	if typeID == "jwt" {
		if keyID, ok := newData["key_id"].(string); ok {
			metadata.KeyID = keyID
		}
		if algorithm, ok := newData["algorithm"].(string); ok {
			metadata.Algorithm = algorithm
		}
	}

	// Convert metadata to JSON
	metadataJSON, err := json.Marshal(metadata)
	if err != nil {
		return fmt.Errorf("failed to marshal updated secret metadata: %w", err)
	}

	// Store updated metadata in Consul
	_, err = api.consulClient.client.KV().Put(&consul.KVPair{
		Key:   fmt.Sprintf("secret-metadata/%s/%s", typeID, secretID),
		Value: metadataJSON,
	}, nil)
	if err != nil {
		return fmt.Errorf("failed to store updated secret metadata in Consul: %w", err)
	}

	return nil
}

// GetSecret retrieves a secret from Vault
func (api *SecretManagementAPI) GetSecret(typeID, secretID string) (map[string]interface{}, error) {
	// Get the secret from Vault
	secret, err := api.vaultClient.client.KVv2("dynamic-secrets").Get(context.Background(), fmt.Sprintf("%s/%s", typeID, secretID))
	if err != nil {
		return nil, fmt.Errorf("failed to get secret from Vault: %w", err)
	}

	return secret.Data, nil
}

// GetServiceSecrets returns a list of secrets that a service has access to
func (api *SecretManagementAPI) GetServiceSecrets(serviceID string) ([]SecretMetadata, error) {
	// Get the service registration
	pair, _, err := api.consulClient.client.KV().Get(fmt.Sprintf("service-registry/%s", serviceID), nil)
	if err != nil {
		return nil, fmt.Errorf("failed to get service registration: %w", err)
	}

	if pair == nil {
		return nil, fmt.Errorf("service %s not found", serviceID)
	}

	var serviceReg ServiceSecretAccess
	if err := json.Unmarshal(pair.Value, &serviceReg); err != nil {
		return nil, fmt.Errorf("failed to unmarshal service registration: %w", err)
	}

	// Collect secrets for each type
	var allSecrets []SecretMetadata
	for _, typeID := range serviceReg.SecretTypes {
		secrets, err := api.consulClient.ListSecrets(typeID)
		if err != nil {
			log.Printf("Warning: failed to list secrets of type %s: %v", typeID, err)
			continue
		}

		// Filter secrets that include this service as a consumer
		for _, secret := range secrets {
			for _, consumer := range secret.Consumers {
				if consumer == serviceID {
					allSecrets = append(allSecrets, secret)
					break
				}
			}
		}
	}

	return allSecrets, nil
}

// handleCreateSecret handles the API endpoint for creating a new secret
func (api *SecretManagementAPI) handleCreateSecret(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req CreateSecretRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, fmt.Sprintf("Invalid request: %v", err), http.StatusBadRequest)
		return
	}

	if err := api.StoreSecret(req); err != nil {
		http.Error(w, fmt.Sprintf("Failed to store secret: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{
		"status":  "success",
		"message": fmt.Sprintf("Secret %s/%s created successfully", req.Type, req.Owner),
	})
}

// handleRotateSecret handles the API endpoint for rotating a secret
func (api *SecretManagementAPI) handleRotateSecret(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Parse path parameters
	pathParts := strings.Split(r.URL.Path, "/")
	if len(pathParts) < 4 {
		http.Error(w, "Invalid path", http.StatusBadRequest)
		return
	}

	typeID := pathParts[len(pathParts)-2]
	secretID := pathParts[len(pathParts)-1]

	// Parse request body for new data
	var newData map[string]interface{}
	if err := json.NewDecoder(r.Body).Decode(&newData); err != nil {
		http.Error(w, fmt.Sprintf("Invalid request: %v", err), http.StatusBadRequest)
		return
	}

	if err := api.RotateSecret(typeID, secretID, newData); err != nil {
		http.Error(w, fmt.Sprintf("Failed to rotate secret: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"status":  "success",
		"message": fmt.Sprintf("Secret %s/%s rotated successfully", typeID, secretID),
	})
}

// handleDeleteSecret handles the API endpoint for deleting a secret
func (api *SecretManagementAPI) handleDeleteSecret(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Parse path parameters
	pathParts := strings.Split(r.URL.Path, "/")
	if len(pathParts) < 4 {
		http.Error(w, "Invalid path", http.StatusBadRequest)
		return
	}

	typeID := pathParts[len(pathParts)-2]
	secretID := pathParts[len(pathParts)-1]

	if err := api.DeleteSecret(typeID, secretID); err != nil {
		http.Error(w, fmt.Sprintf("Failed to delete secret: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"status":  "success",
		"message": fmt.Sprintf("Secret %s/%s deleted successfully", typeID, secretID),
	})
}

// handleGetSecret handles the API endpoint for retrieving a secret
func (api *SecretManagementAPI) handleGetSecret(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Parse path parameters
	pathParts := strings.Split(r.URL.Path, "/")
	if len(pathParts) < 4 {
		http.Error(w, "Invalid path", http.StatusBadRequest)
		return
	}

	typeID := pathParts[len(pathParts)-2]
	secretID := pathParts[len(pathParts)-1]

	secret, err := api.GetSecret(typeID, secretID)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to get secret: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(secret)
}

// handleListSecrets handles the API endpoint for listing secrets of a type
func (api *SecretManagementAPI) handleListSecrets(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Parse path parameters
	pathParts := strings.Split(r.URL.Path, "/")
	if len(pathParts) < 3 {
		http.Error(w, "Invalid path", http.StatusBadRequest)
		return
	}

	typeID := pathParts[len(pathParts)-1]

	secrets, err := api.consulClient.ListSecrets(typeID)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to list secrets: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(secrets)
}

// handleGetSecretTypes handles the API endpoint for retrieving secret types
func (api *SecretManagementAPI) handleGetSecretTypes(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	types, err := api.consulClient.GetSecretTypes()
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to get secret types: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(types)
}

// handleGetServiceSecrets handles the API endpoint for listing a service's accessible secrets
func (api *SecretManagementAPI) handleGetServiceSecrets(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Parse path parameters
	pathParts := strings.Split(r.URL.Path, "/")
	if len(pathParts) < 3 {
		http.Error(w, "Invalid path", http.StatusBadRequest)
		return
	}

	serviceID := pathParts[len(pathParts)-1]

	secrets, err := api.GetServiceSecrets(serviceID)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to get service secrets: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(secrets)
}

// handleHealth is a simple health check endpoint
func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status": "ok",
		"time":   time.Now().Format(time.RFC3339),
	})
}

func main() {
	log.Println("Starting Secret Management API...")

	// Get configuration from environment
	vaultAddr := getEnv("VAULT_ADDR", "http://vault:8200")
	vaultRoleID := getEnv("VAULT_ROLE_ID", "secret-api-role-id")
	vaultSecretID := getEnv("VAULT_SECRET_ID", "secret-api-secret-id")
	consulAddr := getEnv("CONSUL_HTTP_ADDR", "http://consul:8500")
	servicePort := getEnv("SERVICE_PORT", "8300")

	// Create and configure Vault client
	vaultClient, err := NewVaultClient(vaultAddr)
	if err != nil {
		log.Fatalf("Failed to create Vault client: %v", err)
	}

	// Authenticate to Vault
	log.Println("Authenticating to Vault...")
	if err := vaultClient.AuthenticateWithAppRole(vaultRoleID, vaultSecretID); err != nil {
		log.Fatalf("Failed to authenticate to Vault: %v", err)
	}
	log.Println("Successfully authenticated to Vault")

	// Create and configure Consul client
	consulClient, err := NewConsulClient(consulAddr)
	if err != nil {
		log.Fatalf("Failed to create Consul client: %v", err)
	}

	// Create API service
	api := &SecretManagementAPI{
		vaultClient:  vaultClient,
		consulClient: consulClient,
	}

	// Configure HTTP server
	http.HandleFunc("/v1/secrets/create", api.handleCreateSecret)
	http.HandleFunc("/v1/secrets/", func(w http.ResponseWriter, r *http.Request) {
		path := r.URL.Path

		// Handle specific endpoints
		switch {
		case strings.HasPrefix(path, "/v1/secrets/types"):
			api.handleGetSecretTypes(w, r)
		case strings.HasPrefix(path, "/v1/secrets/service/"):
			api.handleGetServiceSecrets(w, r)
		case r.Method == http.MethodGet && strings.Count(path, "/") == 4:
			api.handleGetSecret(w, r)
		case r.Method == http.MethodGet && strings.Count(path, "/") == 3:
			api.handleListSecrets(w, r)
		case r.Method == http.MethodPost && strings.HasSuffix(path, "/rotate"):
			api.handleRotateSecret(w, r)
		case r.Method == http.MethodDelete:
			api.handleDeleteSecret(w, r)
		default:
			http.NotFound(w, r)
		}
	})
	http.HandleFunc("/health", handleHealth)

	// Start HTTP server
	serverAddr := fmt.Sprintf(":%s", servicePort)
	log.Printf("Secret Management API listening on %s", serverAddr)
	if err := http.ListenAndServe(serverAddr, nil); err != nil {
		log.Fatalf("HTTP server failed: %v", err)
	}
}

// getEnv gets an environment variable or returns a default value
func getEnv(key, defaultVal string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return defaultVal
}
