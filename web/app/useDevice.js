'use client';

import { useState, useEffect } from 'react';

const breakpoints = { sm: 640, md: 768, lg: 1024, xl: 1280, tiny: 380 };

function detectCapabilities() {
    if (typeof window === 'undefined') {
        return { isTouch: false, canHover: true, dvhSupported: true };
    }
    const touch = (navigator.maxTouchPoints || 0) > 0 || 'ontouchstart' in window;
    const coarse = window.matchMedia && window.matchMedia('(pointer: coarse)').matches;
    const fine = window.matchMedia && window.matchMedia('(pointer: fine)').matches;
    const hover = window.matchMedia && window.matchMedia('(hover: none)').matches;
    let dvhSupported = true;
    try {
        dvhSupported = typeof CSS !== 'undefined' && CSS.supports ? CSS.supports('height', '100dvh') : true;
    } catch {
        dvhSupported = true;
    }
    return {
        isTouch: touch || coarse,
        isCoarse: coarse,
        canHover: fine && !hover && !coarse,
        dvhSupported,
    };
}

function readViewport() {
    if (typeof window === 'undefined') {
        return { width: 0, height: 0, vh: 0, vvHeight: 0, offsetTop: 0, keyboardOpen: false };
    }
    const w = window.innerWidth || document.documentElement.clientWidth || 0;
    const h = window.innerHeight || document.documentElement.clientHeight || 0;
    const vv = window.visualViewport;
    const vvHeight = vv ? vv.height : h;
    const offsetTop = vv && typeof vv.offsetTop === 'number' ? vv.offsetTop : 0;
    const keyboardOpen = vv ? vv.height < h * 0.6 : false;
    return { width: w, height: h, vh: vvHeight, vvHeight, offsetTop, keyboardOpen };
}

function readSafeArea() {
    if (typeof document === 'undefined') {
        return { top: 0, right: 0, bottom: 0, left: 0 };
    }
    const probe = document.createElement('div');
    probe.style.position = 'fixed';
    probe.style.left = '0';
    probe.style.top = '0';
    probe.style.width = '0';
    probe.style.height = '0';
    probe.style.paddingLeft = 'env(safe-area-inset-left)';
    probe.style.paddingRight = 'env(safe-area-inset-right)';
    probe.style.paddingTop = 'env(safe-area-inset-top)';
    probe.style.paddingBottom = 'env(safe-area-inset-bottom)';
    probe.style.pointerEvents = 'none';
    probe.style.visibility = 'hidden';
    document.body.appendChild(probe);
    const cs = window.getComputedStyle(probe);
    const parse = (v) => Math.max(0, parseFloat(v) || 0);
    const insets = {
        top: parse(cs.paddingTop),
        right: parse(cs.paddingRight),
        bottom: parse(cs.paddingBottom),
        left: parse(cs.paddingLeft),
    };
    document.body.removeChild(probe);
    return insets;
}

export function useDevice() {
    const [device, setDevice] = useState(() => {
        const vp = readViewport();
        const caps = detectCapabilities();
        return {
            isClient: false,
            ...caps,
            ...vp,
            safeArea: { top: 0, right: 0, bottom: 0, left: 0 },
            isMobile: false,
            isTablet: false,
            isDesktop: true,
            isTiny: false,
            portrait: true,
            form: 'desktop',
        };
    });

    useEffect(() => {
        const update = () => {
            const vp = readViewport();
            const caps = detectCapabilities();
            const safeArea = readSafeArea();
            const { width } = vp;
            const isMobile = width < breakpoints.md;
            const isTablet = !isMobile && width < breakpoints.lg;
            const isTiny = width <= breakpoints.tiny;
            setDevice({
                isClient: true,
                ...caps,
                ...vp,
                safeArea,
                isMobile,
                isTablet,
                isDesktop: !isMobile && !isTablet,
                isTiny,
                portrait: vp.height >= vp.width,
                form: isMobile ? 'mobile' : isTablet ? 'tablet' : 'desktop',
            });
        };

        update();

        const vv = window.visualViewport;
        const onVV = () => update();
        if (vv) {
            vv.addEventListener('resize', onVV);
            vv.addEventListener('scroll', onVV);
        }
        window.addEventListener('resize', onVV);
        window.addEventListener('orientationchange', onVV);

        const mqs = ['(pointer: coarse)', '(hover: none)']
            .map(q => window.matchMedia(q))
            .filter(Boolean);
        mqs.forEach(m => m.addEventListener?.('change', onVV));

        return () => {
            if (vv) {
                vv.removeEventListener('resize', onVV);
                vv.removeEventListener('scroll', onVV);
            }
            window.removeEventListener('resize', onVV);
            window.removeEventListener('orientationchange', onVV);
            mqs.forEach(m => m.removeEventListener?.('change', onVV));
        };
    }, []);

    return device;
}
