export type DeviceType = 'mobile' | 'tablet' | 'desktop';

export function getDeviceType(): DeviceType {
  const width = window.innerWidth;

  if (width < 768) {
    return 'mobile';
  } else if (width >= 768 && width < 1024) {
    return 'tablet';
  } else {
    return 'desktop';
  }
}

export function isMobile(): boolean {
  return getDeviceType() === 'mobile';
}

export function isTablet(): boolean {
  return getDeviceType() === 'tablet';
}

export function isDesktop(): boolean {
  return getDeviceType() === 'desktop';
}

export function isTouchDevice(): boolean {
  return (
    'ontouchstart' in window ||
    navigator.maxTouchPoints > 0 ||
    (navigator as any).msMaxTouchPoints > 0
  );
}

export function getViewportDimensions() {
  return {
    width: window.innerWidth,
    height: window.innerHeight,
  };
}

export function isLandscape(): boolean {
  return window.innerWidth > window.innerHeight;
}

export function isPortrait(): boolean {
  return window.innerHeight > window.innerWidth;
}
