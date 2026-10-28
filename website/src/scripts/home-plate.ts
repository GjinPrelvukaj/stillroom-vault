// The home plate: as you scroll down to the picture, the file names under it seal into violet ciphertext, one after
// another, and turn back if you scroll up again. Reduced motion or no scripts: the names stay plain.
import { HEX, reduced, ScrollTrigger } from './gsap';

const plate = document.querySelector<HTMLElement>('[data-plate]');
const figure = plate?.closest('figure');

if (plate && figure && !reduced()) {
  const tiles = [...figure.querySelectorAll<HTMLElement>('[data-tile]')];
  const cipher = () => Array.from({ length: 3 }, () => Array.from({ length: 4 }, () => HEX[Math.floor(Math.random() * 16)]).join('')).join(' ');
  const seal = (done: boolean) =>
    tiles.forEach((t, i) => {
      const name = t.querySelector<HTMLElement>('[data-name]')!;
      // One after another, like files going in.
      window.setTimeout(() => {
        t.classList.toggle('sealed', done);
        name.textContent = done ? cipher() : (name.dataset.name ?? '');
      }, done ? i * 120 : 0);
    });

  // Sealed once the picture's middle is a third of the way down the screen.
  ScrollTrigger.create({
    trigger: plate,
    start: 'center 33%',
    onEnter: () => seal(true),
    onLeaveBack: () => seal(false),
  });
}
