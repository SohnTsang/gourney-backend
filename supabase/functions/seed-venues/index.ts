// seedVenues.ts
// Run this script to seed 150 venues into the database

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

interface VenueData {
  provider: string;
  provider_place_id: string;
  name_ja: string | null;
  name_en: string | null;
  name_zh: string | null;
  city: string;
  ward?: string;
  prefecture_name?: string;
  prefecture_code?: string;
  lat: number;
  lng: number;
  price_level: number | null;
  categories: string[];
}

async function seedVenue(venue: VenueData) {
  try {
    const { data, error } = await supabase.rpc('upsert_place', {
      p_provider: venue.provider,
      p_provider_place_id: venue.provider_place_id,
      p_name_ja: venue.name_ja || null,
      p_name_en: venue.name_en || null,
      p_name_zh: venue.name_zh || null,
      p_postal_code: null,
      p_prefecture_code: venue.prefecture_code || null,
      p_prefecture_name: venue.prefecture_name || null,
      p_ward: venue.ward || null,
      p_city: venue.city,
      p_lat: venue.lat,
      p_lng: venue.lng,
      p_price_level: venue.price_level,
      p_categories: venue.categories,
    });

    if (error) {
      console.error(`❌ Failed to insert ${venue.name_en}:`, error);
      return { success: false, venue: venue.name_en, error };
    }

    console.log(`✅ Inserted: ${venue.name_en} (${venue.city})`);
    return { success: true, venue: venue.name_en, id: data };
  } catch (err) {
    console.error(`❌ Exception for ${venue.name_en}:`, err);
    return { success: false, venue: venue.name_en, error: err };
  }
}

async function main() {
  console.log('🚀 Starting venue seeding process...\n');

  // Load the JSON file
  const venuesJson = await Deno.readTextFile('./seed_venues_150.json');
  const { venues } = JSON.parse(venuesJson);

  console.log(`📊 Total venues to insert: ${venues.length}\n`);

  const results = {
    total: venues.length,
    success: 0,
    failed: 0,
    errors: [] as any[],
  };

  // Process in batches of 10 to avoid rate limits
  const BATCH_SIZE = 10;
  for (let i = 0; i < venues.length; i += BATCH_SIZE) {
    const batch = venues.slice(i, i + BATCH_SIZE);
    console.log(`\n📦 Processing batch ${Math.floor(i / BATCH_SIZE) + 1} (venues ${i + 1}-${Math.min(i + BATCH_SIZE, venues.length)})`);

    const batchResults = await Promise.all(batch.map(seedVenue));

    batchResults.forEach(result => {
      if (result.success) {
        results.success++;
      } else {
        results.failed++;
        results.errors.push(result);
      }
    });

    // Small delay between batches
    if (i + BATCH_SIZE < venues.length) {
      await new Promise(resolve => setTimeout(resolve, 500));
    }
  }

  console.log('\n' + '='.repeat(60));
  console.log('📈 SEEDING COMPLETE');
  console.log('='.repeat(60));
  console.log(`✅ Successfully inserted: ${results.success}/${results.total}`);
  console.log(`❌ Failed: ${results.failed}/${results.total}`);

  if (results.errors.length > 0) {
    console.log('\n❌ Failed venues:');
    results.errors.forEach(err => {
      console.log(`  - ${err.venue}: ${err.error.message || err.error}`);
    });
  }

  console.log('\n✨ Done!');
}

// Run the script
if (import.meta.main) {
  main().catch(console.error);
}