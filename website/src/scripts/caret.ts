// The seal box's caret: a violet bar that glides to wherever you type or click (after Skiper UI's 106 Smooth caret
// input). The textarea stays a real one, so selection, input methods, paste, spelling and screen readers are all the
// browser's own; this only hides the native caret and draws one in its place, found by laying the text up to the caret
// out in a hidden copy of the box. While an input method is composing, and with reduced motion, the native caret shows.
import { reduced } from './gsap';

const COPIED = [
  'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft', 'fontFamily', 'fontSize', 'fontWeight',
  'fontStyle', 'fontStretch', 'fontVariant', 'fontFeatureSettings', 'fontKerning', 'lineHeight', 'letterSpacing',
  'wordSpacing', 'textIndent', 'textTransform', 'tabSize',
] as const;

function smoothCaret(wrap: HTMLElement) {
  const field = wrap.querySelector('textarea');
  if (!field) return;
  const caret = document.createElement('span');
  caret.className = 'glide-caret';
  caret.setAttribute('aria-hidden', 'true');
  const mirror = document.createElement('div');
  mirror.className = 'caret-mirror';
  mirror.setAttribute('aria-hidden', 'true');
  const mark = document.createElement('span');
  wrap.append(mirror, caret);
  wrap.classList.add('smooth');

  let composing = false;
  let queued = false;
  let lastX = -1;
  let lastY = -1;

  const place = () => {
    queued = false;
    const focused = document.activeElement === field;
    const collapsed = field.selectionStart === field.selectionEnd;
    if (!focused || composing || !collapsed) {
      wrap.classList.remove('shown', 'gliding');
      return;
    }
    const css = getComputedStyle(field);
    for (const p of COPIED) mirror.style[p] = css[p];
    mirror.style.width = `${field.clientWidth}px`;
    mirror.textContent = field.value.slice(0, field.selectionEnd);
    mark.textContent = '​';
    mirror.append(mark);
    const height = Math.round(parseFloat(css.fontSize) * 1.2);
    const x = field.offsetLeft + field.clientLeft + mark.offsetLeft - field.scrollLeft;
    // Centred on the marker's own line, whatever the line height.
    const y = field.offsetTop + field.clientTop + mark.offsetTop + mark.offsetHeight / 2 - height / 2 - field.scrollTop;
    // Hidden when the caret is scrolled out of the box.
    const top = field.offsetTop + field.clientTop;
    const inside = y >= top - 1 && y + height <= top + field.clientHeight + 1;
    wrap.classList.toggle('shown', inside);
    if (x === lastX && y === lastY) return;
    // It glides between spots once it's showing, and jumps straight there when it first appears.
    wrap.classList.toggle('gliding', lastX >= 0);
    lastX = x;
    lastY = y;
    caret.style.height = `${height}px`;
    caret.style.transform = `translate(${x}px, ${y}px)`;
    // Restart the blink, so it holds still while you type.
    caret.style.animation = 'none';
    void caret.offsetWidth;
    caret.style.animation = '';
  };
  const later = () => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(place);
  };

  field.addEventListener('focus', later);
  field.addEventListener('blur', () => {
    lastX = lastY = -1;
    later();
  });
  field.addEventListener('input', later);
  field.addEventListener('scroll', later);
  field.addEventListener('keyup', later);
  field.addEventListener('pointerup', later);
  document.addEventListener('selectionchange', () => {
    if (document.activeElement === field) later();
  });
  field.addEventListener('compositionstart', () => {
    composing = true;
    wrap.classList.remove('smooth');
    later();
  });
  field.addEventListener('compositionend', () => {
    composing = false;
    wrap.classList.add('smooth');
    lastX = lastY = -1;
    later();
  });
  new ResizeObserver(later).observe(field);
}

if (!reduced()) document.querySelectorAll<HTMLElement>('[data-smooth-caret]').forEach(smoothCaret);
