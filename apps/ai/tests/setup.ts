import { blockExternalFetch, scrubAmbientEnv } from './helpers/hermetic.js';

// Runs before every test file: see helpers/hermetic.ts.
scrubAmbientEnv(process.env);
blockExternalFetch();
