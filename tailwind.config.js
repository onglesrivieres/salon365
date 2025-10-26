/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      screens: {
        'xs': '375px',
        'iphone': '390px',
        'ipad': '810px',
        'custom': '956px',
      },
    },
  },
  plugins: [],
};
