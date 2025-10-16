import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { validatePhotoUrls, generatePhotoPath } from '../_shared/photoUrlValidator.ts';

serve(async (req) => {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  
  // Test cases
  const tests = {
    // Valid case
    valid: [`${supabaseUrl}/storage/v1/object/public/user-photos/user123/2024/01/photo.jpg`],
    // Invalid - external URL
    invalid_external: ['https://example.com/photo.jpg'],
    // Invalid - too many photos
    too_many: [
      `${supabaseUrl}/storage/v1/object/public/user-photos/1.jpg`,
      `${supabaseUrl}/storage/v1/object/public/user-photos/2.jpg`,
      `${supabaseUrl}/storage/v1/object/public/user-photos/3.jpg`,
      `${supabaseUrl}/storage/v1/object/public/user-photos/4.jpg`,
    ],
    // Invalid - wrong bucket
    wrong_bucket: [`${supabaseUrl}/storage/v1/object/public/other-bucket/photo.jpg`],
  };
  
  const results = {};
  
  for (const [testName, urls] of Object.entries(tests)) {
    results[testName] = await validatePhotoUrls(urls, supabaseUrl);
  }
  
  // Test path generation
  const newPath = generatePhotoPath('user123', 'image/jpeg');
  
  return new Response(
    JSON.stringify({
      tests: results,
      generatedPath: newPath
    }, null, 2),
    { headers: { 'Content-Type': 'application/json' } }
  );
});