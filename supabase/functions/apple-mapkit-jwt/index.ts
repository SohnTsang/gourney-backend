// supabase/functions/apple-mapkit-jwt/index.ts
// Generates JWT token for Apple MapKit JS API
// PUBLIC ENDPOINT - No authentication required

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};

serve(async (req) => {
  // Handle preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // Only allow GET
  if (req.method !== 'GET') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      {
        status: 405,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );
  }

  try {
    const privateKey = Deno.env.get('APPLE_MAPKIT_PRIVATE_KEY');
    const keyId = Deno.env.get('APPLE_MAPKIT_KEY_ID');
    const teamId = Deno.env.get('APPLE_MAPKIT_TEAM_ID');

    if (!privateKey || !keyId || !teamId) {
      console.error('Missing Apple MapKit credentials');
      return new Response(
        JSON.stringify({ 
          error: 'Configuration error',
          message: 'Apple MapKit credentials not configured'
        }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      );
    }

    console.log('Generating Apple MapKit JWT...');

    // Import jose for JWT signing
    const { SignJWT, importPKCS8 } = await import('https://deno.land/x/jose@v5.2.0/index.ts');

    // Import the private key
    const key = await importPKCS8(privateKey, 'ES256');

    // Create JWT
    const now = Math.floor(Date.now() / 1000);
    const token = await new SignJWT({})
      .setProtectedHeader({ 
        alg: 'ES256',
        kid: keyId,
        typ: 'JWT'
      })
      .setIssuer(teamId)
      .setIssuedAt(now)
      .setExpirationTime(now + 3600) // 1 hour
      .sign(key);

    console.log('JWT generated successfully');

    return new Response(
      JSON.stringify({ 
        token,
        expires_at: now + 3600
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );
  } catch (error) {
    console.error('JWT generation error:', error);
    return new Response(
      JSON.stringify({ 
        error: 'Failed to generate JWT',
        message: error.message 
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );
  }
});