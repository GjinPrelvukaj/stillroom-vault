// Small pieces the tools share: a copy button and a place to drop, choose or paste a file.

/** Copies text when clicked, and says "Copied" on the button for a moment. The label is the button's last <span>. */
export function copyButton(button: HTMLButtonElement, text: () => string) {
  const label = button.querySelector('span:last-of-type') ?? button;
  const was = label.textContent;
  button.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(text());
      label.textContent = 'Copied';
    } catch {
      label.textContent = 'Select and copy it';
    }
    setTimeout(() => (label.textContent = was), 1500);
  });
}

/** Calls back with a file dropped on the box, chosen with its file input, or pasted anywhere on the page. */
export function dropZone(box: HTMLElement, onFile: (file: File) => void, { paste = false } = {}) {
  const input = box.querySelector<HTMLInputElement>('input[type=file]')!;
  input.addEventListener('change', () => input.files?.[0] && onFile(input.files[0]));
  box.addEventListener('dragover', (e) => {
    e.preventDefault();
    box.classList.add('over');
  });
  box.addEventListener('dragleave', () => box.classList.remove('over'));
  box.addEventListener('drop', (e) => {
    e.preventDefault();
    box.classList.remove('over');
    const file = e.dataTransfer?.files[0];
    if (file) onFile(file);
  });
  if (paste)
    document.addEventListener('paste', (e) => {
      const file = [...(e.clipboardData?.files ?? [])][0];
      if (file) onFile(file);
    });
}
