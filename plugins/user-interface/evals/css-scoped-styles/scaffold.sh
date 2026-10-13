#!/usr/bin/env bash
# Seeds a small Vue app whose components use scoped styles.
set -euo pipefail

mkdir -p src/components
cat > package.json <<'JSON'
{ "name": "shopfront", "private": true, "type": "module",
  "scripts": { "build": "vite build" },
  "dependencies": { "vue": "^3.5.0" },
  "devDependencies": { "vite": "^6.0.0", "@vitejs/plugin-vue": "^5.2.0" } }
JSON
cat > vite.config.js <<'JS'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
export default defineConfig({ plugins: [vue()] })
JS
cat > src/components/PriceTag.vue <<'VUE'
<template>
  <div class="price-tag">
    <span class="price">{{ price }}</span>
    <span v-if="onSale" class="sale-badge">Sale</span>
    <InfoLink class="info" :href="href" />
  </div>
</template>

<script setup>
import InfoLink from './InfoLink.vue'
defineProps({ price: String, href: String, onSale: Boolean })
</script>

<style scoped>
.price-tag { display: flex; align-items: center; gap: 0.5rem; }
.price { font-weight: 600; }
</style>
VUE
cat > src/components/InfoLink.vue <<'VUE'
<template>
  <a class="info-link" :href="href"><span class="info-link__icon">i</span> Details</a>
</template>

<script setup>
defineProps({ href: String })
</script>

<style scoped>
.info-link { text-decoration: none; color: inherit; }
</style>
VUE
