// The release list read from CHANGELOG.md, which the update note, the feed and the update email all rest on.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { compareVersions, parseReleases } from '../src/lib/releases.ts';
import { updateEmail } from '../emails/update.ts';

const md = `# Changelog

## [Unreleased]
- Not out yet.

## [1.0.1] - 2027-02-03

Fixes a problem a reader reported.

### Security
- A [doctored](https://example.com) backup can no longer \`crash\` restore.

### Fixed
- Search finds accented words.

## [1.0.0] - 2027-01-15
- First release.
`;

test('released versions are read, newest first, with security releases marked', () => {
  const [newest, first, ...rest] = parseReleases(md);
  assert.equal(rest.length, 0, 'Unreleased is skipped');
  assert.deepEqual(newest, {
    version: '1.0.1',
    date: '2027-02-03',
    security: true,
    slug: '101---2027-02-03',
    intro: 'Fixes a problem a reader reported.',
    notes: ['A doctored backup can no longer crash restore.', 'Search finds accented words.'],
  });
  assert.equal(first?.security, false);
  assert.equal(first?.intro, '');
});

test('versions compare as numbers', () => {
  assert.equal(compareVersions('1.0.10', '1.0.9'), 1);
  assert.equal(compareVersions('1.0.0', '1.0.0'), 0);
  assert.equal(compareVersions('0.9.0', '1.0.0'), -1);
});

test('the update email says when it fixes a security problem, and how to update', () => {
  const [newest] = parseReleases(md);
  const mail = updateEmail(newest!);
  assert.match(mail.subject, /1\.0\.1: a security update/);
  assert.match(mail.text, /fixes a security problem/);
  assert.match(mail.text, /changelog\/#101---2027-02-03/);
  assert.ok(mail.html.includes('Download 1.0.1'));
});
