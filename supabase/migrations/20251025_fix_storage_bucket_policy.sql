-- Fix visit-photos bucket RLS policies
-- Allows authenticated users to upload their own photos

-- Drop existing policies if any
DROP POLICY IF EXISTS "Users can upload their own photos" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can view photos" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own photos" ON storage.objects;

-- Policy 1: Allow authenticated users to INSERT photos into their own folder
CREATE POLICY "Users can upload their own photos"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'visit-photos' 
    AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Policy 2: Allow public READ access to all photos
CREATE POLICY "Anyone can view photos"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'visit-photos');

-- Policy 3: Allow users to DELETE their own photos
CREATE POLICY "Users can delete their own photos"
ON storage.objects
FOR DELETE
TO authenticated
USING (
    bucket_id = 'visit-photos' 
    AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Ensure bucket is public for reads
UPDATE storage.buckets 
SET public = true 
WHERE id = 'visit-photos';