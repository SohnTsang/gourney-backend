-- Migration: 20251007_add_missing_list_columns.sql
-- Adds columns required by roadmap that are missing from current schema

-- Add description to lists table
ALTER TABLE lists 
ADD COLUMN IF NOT EXISTS description TEXT;

-- Add note column to list_items and id as primary key
ALTER TABLE list_items
ADD COLUMN IF NOT EXISTS note TEXT CHECK (char_length(note) <= 200),
ADD COLUMN IF NOT EXISTS id UUID DEFAULT gen_random_uuid();

-- Make id the primary key (after adding it)
-- First, drop existing primary key if it exists
ALTER TABLE list_items DROP CONSTRAINT IF EXISTS list_items_pkey;

-- Add new primary key on id
ALTER TABLE list_items ADD PRIMARY KEY (id);

-- Keep unique constraint on (list_id, place_id) to prevent duplicates
ALTER TABLE list_items 
ADD CONSTRAINT list_items_list_place_unique 
UNIQUE (list_id, place_id);

-- Add constraints for lists.description
ALTER TABLE lists
ADD CONSTRAINT lists_description_length CHECK (
  description IS NULL OR char_length(description) <= 500
);

