#!/usr/bin/env node

const fs = require('fs');
const { JSDOM } = require('jsdom');

const htmlPath = process.argv[2];
if (!htmlPath) {
  console.error('usage: verify_dom.js RESPONSE_BODY');
  process.exit(2);
}

const html = fs.readFileSync(htmlPath, 'utf8');
const dom = new JSDOM(html, { runScripts: 'dangerously' });
const value = dom.window.document.body.getAttribute('data-xss') || '';
console.log(`body_data_xss=${value}`);

if (value !== 'XSS_MARKER') {
  console.error('DOM execution oracle was not observed');
  process.exit(1);
}
