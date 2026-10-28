// The decoy diagram: guess which slot is yours (a coin toss, as for anyone with the folder), and the lenses light what
// each onlooker can see.
const diagram = document.querySelector<HTMLElement>('[data-decoy]');
const tabs = document.querySelector<HTMLElement>('[data-lens-tabs]');

if (diagram) {
  const answer = diagram.querySelector<HTMLElement>('[data-answer]')!;
  const slots = [...diagram.querySelectorAll<HTMLElement>('[data-slot]')];
  let guesses = 0;
  let right = 0;
  diagram.querySelectorAll<HTMLButtonElement>('[data-pick]').forEach((button) => {
    button.addEventListener('click', () => {
      // A new vault goes in a or b at random, and nothing records which.
      const yours = crypto.getRandomValues(new Uint8Array(1))[0]! & 1 ? 'a' : 'b';
      const guess = button.dataset.pick;
      guesses += 1;
      if (guess === yours) right += 1;
      slots.forEach((s) => s.classList.toggle('is-yours', s.dataset.slot === yours));
      answer.innerHTML =
        `This time it was <strong>${yours}/</strong>. ` +
        (guess === yours ? 'You guessed right, by luck: ' : 'You guessed wrong, and no wonder: ') +
        'the letters, the files, their sizes and their dates are the same in both. ' +
        `So far: ${right} of ${guesses}.`;
    });
  });
}

tabs?.addEventListener('segment-change', (e) => {
  const lens = (e as CustomEvent<string>).detail;
  if (diagram) diagram.dataset.lens = lens;
});
