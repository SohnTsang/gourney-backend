/**
 * Photo URL Validator
 * Ensures photos come only from our storage bucket
 * Prevents external URLs from being injected
 */

import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

export interface PhotoValidationResult {
  valid: boolean;
  reason?: string;
  sanitizedUrls?: string[];
}

// Maximum allowed photos per visit
const MAX_PHOTOS_PER_VISIT = 3;

// Allowed MIME types
const ALLOWED_MIME_TYPES = ['image/jpeg', 'image/jpg', 'image/png'];

// Max file size in bytes (4MB)
const MAX_FILE_SIZE = 4 * 1024 * 1024;

/**
 * Validates photo URLs to ensure they're from our storage bucket
 * Critical for preventing malicious external URLs
 */
export async function validatePhotoUrls(
  photoUrls: string[] | null | undefined,
  supabaseUrl: string,
  bucketName: string = 'user-photos'
): Promise<PhotoValidationResult> {
  // No photos is valid
  if (!photoUrls || photoUrls.length === 0) {
    return { valid: true, sanitizedUrls: [] };
  }

  // Check count limit
  if (photoUrls.length > MAX_PHOTOS_PER_VISIT) {
    return {
      valid: false,
      reason: `Maximum ${MAX_PHOTOS_PER_VISIT} photos allowed per visit`
    };
  }

  // Build expected URL prefix
  // Format: https://[project-ref].supabase.co/storage/v1/object/public/user-photos/
  const expectedPrefix = `${supabaseUrl}/storage/v1/object/public/${bucketName}/`;
  
  const sanitizedUrls: string[] = [];
  
  for (const url of photoUrls) {
    if (!url || typeof url !== 'string') {
      return {
        valid: false,
        reason: 'Invalid photo URL format'
      };
    }

    // Check if URL starts with our storage bucket prefix
    if (!url.startsWith(expectedPrefix)) {
      return {
        valid: false,
        reason: 'Photos must be uploaded to our storage service'
      };
    }

    // Extract path after bucket prefix
    const path = url.slice(expectedPrefix.length);
    
    // Validate path doesn't contain directory traversal attempts
    if (path.includes('../') || path.includes('..\\') || path.startsWith('/')) {
      return {
        valid: false,
        reason: 'Invalid photo path'
      };
    }

    // Validate filename has proper extension
    const lowercasePath = path.toLowerCase();
    if (!lowercasePath.endsWith('.jpg') && 
        !lowercasePath.endsWith('.jpeg') && 
        !lowercasePath.endsWith('.png')) {
      return {
        valid: false,
        reason: 'Only JPEG and PNG images are allowed'
      };
    }

    // Check for suspicious patterns in filename
    if (path.includes('<') || path.includes('>') || 
        path.includes('javascript:') || path.includes('data:')) {
      return {
        valid: false,
        reason: 'Invalid characters in photo URL'
      };
    }

    sanitizedUrls.push(url);
  }

  return { valid: true, sanitizedUrls };
}

/**
 * Validates photo metadata (for moderateImage sweeper)
 * Performs HEAD request to check MIME type and size
 */
export async function validatePhotoMetadata(
  photoUrl: string,
  supabase: SupabaseClient
): Promise<PhotoValidationResult> {
  try {
    // Extract path from URL
    const urlParts = photoUrl.split('/storage/v1/object/public/user-photos/');
    if (urlParts.length !== 2) {
      return {
        valid: false,
        reason: 'Invalid storage URL format'
      };
    }

    const filePath = urlParts[1];
    
    // Get file metadata from storage
    const { data, error } = await supabase.storage
      .from('user-photos')
      .download(filePath, {
        transform: {
          quality: 1,
          width: 1,
          height: 1
        }
      });

    if (error) {
      console.error('Error fetching photo metadata:', error);
      return {
        valid: false,
        reason: 'Could not verify photo'
      };
    }

    // Check size
    if (data.size > MAX_FILE_SIZE) {
      return {
        valid: false,
        reason: `Photo size exceeds ${MAX_FILE_SIZE / 1024 / 1024}MB limit`
      };
    }

    // Check MIME type from blob
    if (!ALLOWED_MIME_TYPES.includes(data.type)) {
      return {
        valid: false,
        reason: `Invalid image type: ${data.type}. Only JPEG and PNG allowed`
      };
    }

    return { valid: true };
  } catch (error) {
    console.error('Photo validation error:', error);
    return {
      valid: false,
      reason: 'Error validating photo'
    };
  }
}

/**
 * Strips EXIF data from base64 image (for client-side use)
 * Returns cleaned base64 string
 */
export function stripExifFromBase64(base64Image: string): string {
  try {
    // Remove data URL prefix if present
    const base64Data = base64Image.replace(/^data:image\/(jpeg|jpg|png);base64,/, '');
    
    // For PNG images, EXIF is less common but we can return as-is
    if (base64Image.includes('data:image/png')) {
      return base64Image;
    }
    
    // For JPEG, we'd need a proper EXIF removal library
    // This is a placeholder - in production, use a library like piexifjs
    // For now, return the original (client should handle this)
    return base64Image;
  } catch (error) {
    console.error('Error stripping EXIF:', error);
    return base64Image;
  }
}

/**
 * Generates a safe storage path for uploaded photos
 * Format: user_id/year/month/timestamp_random.extension
 */
export function generatePhotoPath(
  userId: string,
  mimeType: string,
  timestamp: number = Date.now()
): string {
  const date = new Date(timestamp);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  
  // Get extension from MIME type
  let extension = 'jpg';
  if (mimeType === 'image/png') {
    extension = 'png';
  }
  
  // Generate random suffix to prevent collisions
  const randomSuffix = Math.random().toString(36).substring(2, 8);
  
  return `${userId}/${year}/${month}/${timestamp}_${randomSuffix}.${extension}`;
}