#!/usr/bin/env bash

set -o errexit
set -o pipefail
shopt -s extglob

ssh_usage() {
  echo -e "
pass ssh [--clip|-c]|[--save,-s] [--private|-p] pass-name
    Get SSH key from password store.
    If --private|-p, output private key (default public key).
    If --clip|-c, copy SSH public key to clipboard and clear automatically after 45 seconds.
    If --save|-s, save to tmp file and echo filename.

pass ssh --generate|-g [--type <s>,-t <s>] pass-name
    Generate a new SSH key to add to the password store.

    Example: pass ssh -g servers/web/proxy01
    servers/web/proxy01 is the pass path and doesn't affect the SSH connection.

    Default type is ed25519 with 100 KDF rounds.
"
}

ssh_short_usage() {
  echo "Usage: pass ssh" \
    "[--help,-h]" \
    "[--generate,-g]" \
    "[--type <s>,-t <s>]" \
    "[--clip,-c]|[--save,-c]" \
    "[--private,-p]" \
    "pass-name [args]"
}

ssh_main() {
  local positionals
  local b_generate=0
  local b_clip=0
  local b_save=0
  local b_private=0
  local key_type="ed25519"

  positionals=()
  while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
    -h | --help)
      ssh_short_usage
      ssh_usage
      exit 1
      ;;
    -t | --type)
      key_type="$2"
      shift # past argument
      shift # past value
      ;;
    -g | --generate)
      b_generate=1
      shift # past argument
      ;;
    -c | --clip)
      b_clip=1
      shift # past argument
      ;;
    -s | --save)
      b_save=1
      shift # past argument
      ;;
    -p | --private)
      b_private=1
      shift # past argument
      ;;
    *) # unknown option
      positionals+=("$1") # append positional argument
      shift               # past argument
      ;;
    esac
  done
  set -- "${positionals[@]}" # restore positional parameters

  path="${positionals[0]}"
  if [ -z "$path" ]; then
    ssh_short_usage
    exit 1
  fi
  check_sneaky_paths "$path" # function provided by pass to check path traversal

  # If generate mode
  if [ "$b_generate" == 1 ]; then
    rm -f /tmp/pass-ssh-key

    # Prompt before overwriting if pass entry already exists
    if pass "$path" >/dev/null; then
      read -p "An entry already exists for $1. Overwrite it? [y/N] " -n 1 -r && echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        exit 1
      fi
    fi

    ssh-keygen -q -a 100 -t "$key_type" -f /tmp/pass-ssh-key
    cat /tmp/pass-ssh-key.pub /tmp/pass-ssh-key | pass insert --multiline "$path" >/dev/null
    rm -f /tmp/pass-ssh-key
  else # Connection mode
    full_file=$(pass "$path")
    public_key=$(pass "$path" | grep -oP 'ssh-.*')
    private_key=$(echo "$full_file" | sed -n -e '/BEGIN.*PRIVATE KEY/,/END.*PRIVATE KEY/ p')

    if [ "$b_private" == 1 ]; then
      target_output="$private_key"
    else
      target_output="$public_key"
    fi

    if [ "$b_clip" == 1 ]; then # Copy to clipboard
      clip "$target_output" "$path"
    elif [ "$b_save" == 1 ]; then # Save private key to file
      tmp_file=$(mktemp)
      echo -e "$target_output" >"$tmp_file"
      echo "$tmp_file"
    else
      echo "$target_output"
    fi
  fi
}

ssh_main "$@"
