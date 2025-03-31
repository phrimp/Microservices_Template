#!/bin/bash
# vault-secrets-loader.sh - Script to dynamically load secrets from files into Vault
# Usage: ./vault-secrets-loader.sh [--format json|yaml|env] [--path /path/to/secrets] [--mount kv] [--prefix secrets/]

set -e

# Default values
SECRETS_PATH="/vault/secrets"
MOUNT_PATH="kv"
SECRET_PREFIX=""
RECURSIVE=false
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
  --format)
    FORMAT="$2"
    shift
    shift
    ;;
  --path)
    SECRETS_PATH="$2"
    shift
    shift
    ;;
  --mount)
    MOUNT_PATH="$2"
    shift
    shift
    ;;
  --prefix)
    SECRET_PREFIX="$2"
    shift
    shift
    ;;
  --recursive)
    RECURSIVE=true
    shift
    ;;
  --dry-run)
    DRY_RUN=true
    shift
    ;;
  --help)
    echo "Usage: ./vault-secrets-loader.sh [OPTIONS]"
    echo "Options:"
    echo "  --format json|yaml|env     Format of secret files (default: env)"
    echo "  --path /path/to/secrets    Path to directory containing secrets (default: /vault/secrets)"
    echo "  --mount kv                 Vault mount point (default: kv)"
    echo "  --prefix secrets/          Prefix for secret paths in Vault (default: none)"
    echo "  --recursive                Process directories recursively (default: false)"
    echo "  --dry-run                  Show what would be done without making changes"
    echo "  --help                     Display this help message"
    exit 0
    ;;
  *)
    echo "Unknown option: $1"
    exit 1
    ;;
  esac
done

# Check for required tools
for cmd in jq vault; do
  if ! command -v $cmd &>/dev/null; then
    echo "Error: $cmd is required but not installed."
    exit 1
  fi
done

# Check if VAULT_ADDR and VAULT_TOKEN are set
if [ -z "$VAULT_ADDR" ]; then
  echo "Error: VAULT_ADDR environment variable not set"
  exit 1
fi

if [ -z "$VAULT_TOKEN" ]; then
  echo "Error: VAULT_TOKEN environment variable not set"
  exit 1
fi

# Function to process a JSON file
process_json_file() {
  local file="$1"
  local vault_path="$2"

  echo "Processing JSON file: $file -> $vault_path"

  # Check if it's a flat JSON (key-value pairs)
  if jq -e 'keys | all(type == "string")' "$file" >/dev/null 2>&1; then
    # It's a flat JSON, we can load it directly
    if [ "$DRY_RUN" = true ]; then
      echo "[DRY RUN] Would write secrets from $file to $vault_path"
      jq -r 'to_entries | map("  \(.key): \(.value)") | .[]' "$file"
    else
      vault kv put "$MOUNT_PATH/data/$vault_path" $(jq -r 'to_entries | map("\(.key)=\(.value)") | join(" ")' "$file")
    fi
  else
    # It's a nested JSON, we need to process each key separately
    jq -r 'paths(scalars) as $p | [$p[] | tostring] | join("/") + "=" + getpath($p) | tostring' "$file" | while read -r line; do
      key=$(echo "$line" | cut -d= -f1)
      value=$(echo "$line" | cut -d= -f2-)

      # Create nested path
      nested_path="${vault_path}/$(dirname "$key")"
      nested_path="${nested_path#./}" # Remove leading ./
      nested_key=$(basename "$key")

      if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would write secret $nested_key to $nested_path"
        echo "  $nested_key: $value"
      else
        mkdir -p "$(dirname "$nested_path")" 2>/dev/null || true
        vault kv put "$MOUNT_PATH/data/$nested_path" "$nested_key=$value"
      fi
    done
  fi
}

# Only process JSON files - removed YAML and ENV file processors

# Function to process files
process_file() {
  local file="$1"
  local rel_path="$2"

  # Skip dotfiles and backup files
  if [[ $(basename "$file") == .* || $(basename "$file") == *~ ]]; then
    return
  fi

  # Determine the vault path based on the file path
  local filename=$(basename "$file" | sed 's/\.[^.]*$//') # Remove extension
  local vault_path

  # If a prefix is provided, use it
  if [ -n "$SECRET_PREFIX" ]; then
    if [ -n "$rel_path" ]; then
      vault_path="${SECRET_PREFIX}${rel_path}/${filename}"
    else
      vault_path="${SECRET_PREFIX}${filename}"
    fi
  else
    if [ -n "$rel_path" ]; then
      vault_path="${rel_path}/${filename}"
    else
      vault_path="${filename}"
    fi
  fi

  # Clean up the path (remove double slashes, etc.)
  vault_path=$(echo "$vault_path" | sed 's|//|/|g' | sed 's|/$||')

  # Only process JSON files
  if [[ "$file" == *.json ]]; then
    process_json_file "$file" "$vault_path"
  else
    echo "Skipping non-JSON file: $file"
  fi
}

# Function to process directories recursively
process_directory() {
  local dir="$1"
  local rel_path="$2"

  echo "Processing directory: $dir"

  # Process all files in the directory
  for file in "$dir"/*; do
    if [ -f "$file" ]; then
      process_file "$file" "$rel_path"
    elif [ -d "$file" ] && [ "$RECURSIVE" = true ]; then
      local new_rel_path
      if [ -n "$rel_path" ]; then
        new_rel_path="${rel_path}/$(basename "$file")"
      else
        new_rel_path="$(basename "$file")"
      fi
      process_directory "$file" "$new_rel_path"
    fi
  done
}

# Main execution
echo "Starting Vault JSON secrets loader with the following configuration:"
echo "  Secrets path: $SECRETS_PATH"
echo "  Vault mount path: $MOUNT_PATH"
echo "  Secret prefix: $SECRET_PREFIX"
echo "  Recursive: $RECURSIVE"
echo "  Dry run: $DRY_RUN"
echo "  Vault address: $VAULT_ADDR"

# Check if secrets path exists
if [ ! -d "$SECRETS_PATH" ] && [ ! -f "$SECRETS_PATH" ]; then
  echo "Error: Secrets path $SECRETS_PATH does not exist"
  exit 1
fi

# Process secrets path
if [ -f "$SECRETS_PATH" ]; then
  # It's a single file
  process_file "$SECRETS_PATH" ""
elif [ -d "$SECRETS_PATH" ]; then
  # It's a directory
  process_directory "$SECRETS_PATH" ""
else
  echo "Error: $SECRETS_PATH is neither a file nor a directory"
  exit 1
fi

echo "Secrets loading process completed successfully"
