import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { encodeCursor, decodeCursor } from "../_shared/cursor.ts";

serve(async (req) => {
  const testData = {
    created_at: new Date().toISOString(),
    id: "123e4567-e89b-12d3-a456-426614174000"
  };
  
  const encoded = await encodeCursor(testData);
  const decoded = await decodeCursor(encoded);
  
  return new Response(JSON.stringify({
    original: testData,
    encoded,
    decoded,
    match: JSON.stringify(testData) === JSON.stringify(decoded)
  }), {
    headers: { "Content-Type": "application/json" }
  });
});