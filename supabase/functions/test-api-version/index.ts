import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { withApiVersion, checkApiVersion } from '../_shared/apiVersionGuard.ts';

// Create handler with version checking
const handler = async (req: Request) => {
  const url = new URL(req.url);
  const versionCheck = checkApiVersion(req);
  
  return new Response(
    JSON.stringify({
      path: url.pathname,
      versionCheck,
      headers: Object.fromEntries(req.headers.entries())
    }, null, 2),
    { headers: { 'Content-Type': 'application/json' } }
  );
};

// Wrap with version middleware
serve(withApiVersion(handler));