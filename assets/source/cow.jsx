// Cow mascot — picks one of the 8 brand-asset poses.
const WNF_MASCOT_ROOT = window.location.pathname.includes('/assets/source/')
  ? '../mascot/'
  : 'assets/mascot/';

const COW_POSES = {
  'front-sad':   WNF_MASCOT_ROOT + 'cow-0-front-sad.png',
  'three-q':     WNF_MASCOT_ROOT + 'cow-1-three-q-sad.png',
  'side-back':   WNF_MASCOT_ROOT + 'cow-2-side-back.png',
  'front-sad-2': WNF_MASCOT_ROOT + 'cow-3-front-sad-2.png',
  'back':        WNF_MASCOT_ROOT + 'cow-4-back.png',
  'back-tail':   WNF_MASCOT_ROOT + 'cow-5-back-tail.png',
  'side-look':   WNF_MASCOT_ROOT + 'cow-6-side-look.png',
  'three-q-2':   WNF_MASCOT_ROOT + 'cow-7-three-q-sad-2.png',
};

function Cow({ pose = 'three-q', size = 200, style = {} }) {
  return (
    <img
      src={COW_POSES[pose] || COW_POSES['three-q']}
      width={size} height={size}
      alt="窝囊牛"
      style={{
        width: size, height: 'auto',
        userSelect: 'none', pointerEvents: 'none',
        ...style,
      }}
    />
  );
}

Object.assign(window, { Cow, COW_POSES, WNF_MASCOT_ROOT });
