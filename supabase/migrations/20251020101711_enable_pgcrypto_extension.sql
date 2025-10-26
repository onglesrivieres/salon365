/*
  # Enable pgcrypto Extension

  1. Extension
    - Enable pgcrypto for cryptographic functions
    - Required for bcrypt password hashing (crypt, gen_salt)
*/

-- Enable pgcrypto extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pgcrypto;
