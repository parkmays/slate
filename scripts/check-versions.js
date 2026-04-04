#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

// Read contract versions
const contracts = {
    dataModel: JSON.parse(fs.readFileSync('contracts/data-model.json', 'utf8')),
    syncApi: JSON.parse(fs.readFileSync('contracts/sync-api.json', 'utf8')),
    aiScoresApi: JSON.parse(fs.readFileSync('contracts/ai-scores-api.json', 'utf8')),
    webApi: JSON.parse(fs.readFileSync('contracts/web-api.json', 'utf8')),
    realtimeEvents: JSON.parse(fs.readFileSync('contracts/realtime-events.json', 'utf8'))
};

// Extract versions
const versions = {
    dataModel: contracts.dataModel.version || '1.0',
    syncApi: contracts.syncApi.version || '1.0',
    aiScoresApi: contracts.aiScoresApi.version || '1.0',
    webApi: contracts.webApi.version || '1.0',
    realtimeEvents: contracts.realtimeEvents.version || '1.0'
};

console.log('Contract Versions:');
console.log('  data-model.json:', versions.dataModel);
console.log('  sync-api.json:', versions.syncApi);
console.log('  ai-scores-api.json:', versions.aiScoresApi);
console.log('  web-api.json:', versions.webApi);
console.log('  realtime-events.json:', versions.realtimeEvents);

// Check for version mismatches
const uniqueVersions = new Set(Object.values(versions));
if (uniqueVersions.size > 1) {
    console.error('\n❌ Version mismatch detected! All contracts should have the same version.');
    console.error('Mismatched versions:', Array.from(uniqueVersions));
    process.exit(1);
}

console.log('\n✅ All contracts have consistent version:', versions.dataModel);

// Check TypeScript types match Swift types
const tsClip = fs.readFileSync('packages/shared-types/src/clip.ts', 'utf8');
const swiftClip = fs.readFileSync('packages/shared-types/Sources/SLATESharedTypes/Clip.swift', 'utf8');

// Extract interfaces from TypeScript
const tsInterfaces = tsClip.match(/export interface \w+ \{[\s\S]*?\n\}/g) || [];
// Extract structs from Swift
const swiftStructs = swiftClip.match(/public struct \w+: .* \{[\s\S]*?\n\}/g) || [];

console.log('\nType Definitions:');
console.log(`  TypeScript interfaces: ${tsInterfaces.length}`);
console.log(`  Swift structs: ${swiftStructs.length}`);

// Basic consistency check
if (Math.abs(tsInterfaces.length - swiftStructs.length) > 2) {
    console.warn('⚠️  Warning: Significant mismatch in type definitions count');
}

console.log('\n✅ Contract version check complete');
