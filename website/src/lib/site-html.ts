// Applied to every page rendered from markdown (the repository's documents and src/content/pages):
// - links to other sites open in a new tab, so the reader keeps their place here;
// - code blocks and tables, which scroll sideways on small screens, can be reached with the keyboard.
export function siteHtml(html: string): string {
  return html
    .replace(/<pre\b/g, '<pre tabindex="0"')
    .replace(/<table>/g, '<table tabindex="0">')
    .replace(/<a href="(https?:\/\/(?!stillroomvault\.com)[^"]+)"/g, '<a href="$1" target="_blank" rel="noopener noreferrer"');
}
