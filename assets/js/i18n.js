/**
 * SchoolAir i18n Engine
 * Lightweight client-side translation system.
 *
 * Usage:
 *   HTML: <span data-i18n="hero.title">Fallback text</span>
 *   JS:   i18n.t('hero.title')
 *   Switch: i18n.load('es')
 */

class I18n {
    constructor() {
        this.translations = {};
        this.supportedLangs = ['en', 'es', 'fr', 'ca', 'it', 'zh'];
        this.langNames = {
            en: 'English',
            es: 'Español',
            fr: 'Français',
            ca: 'Català',
            it: 'Italiano',
            zh: '中文'
        };
        this.currentLang = this._detectLanguage();
        this._ready = this.load(this.currentLang);
    }

    _detectLanguage() {
        // 1. URL param ?lang=xx
        const urlLang = new URLSearchParams(window.location.search).get('lang');
        if (urlLang && this.supportedLangs.includes(urlLang)) return urlLang;

        // 2. Stored preference
        const stored = localStorage.getItem('lang');
        if (stored && this.supportedLangs.includes(stored)) return stored;

        // 3. Browser language
        const nav = (navigator.language || '').slice(0, 2).toLowerCase();
        if (this.supportedLangs.includes(nav)) return nav;

        return 'en';
    }

    async load(lang) {
        if (!this.supportedLangs.includes(lang)) lang = 'en';
        this.currentLang = lang;
        localStorage.setItem('lang', lang);

        try {
            // Resolve path to /lang/ from any page depth
            const base = window.location.pathname.includes('/portal/') ||
                         window.location.pathname.includes('/air-school/')
                ? '/..' : '';
            const resp = await fetch(`/lang/${lang}.json`);
            if (!resp.ok) throw new Error(`Failed to load ${lang}.json`);
            this.translations = await resp.json();
        } catch (err) {
            console.warn(`i18n: Could not load ${lang}.json, falling back to English keys`);
            this.translations = {};
        }

        this.apply();
        return this;
    }

    t(key, fallback) {
        const val = key.split('.').reduce((obj, k) => obj?.[k], this.translations);
        return val || fallback || key;
    }

    apply() {
        // Set lang attribute on html element
        document.documentElement.lang = this.currentLang;

        // Translate elements with data-i18n
        document.querySelectorAll('[data-i18n]').forEach(el => {
            const key = el.getAttribute('data-i18n');
            const val = this.t(key);
            if (val !== key) el.innerHTML = val;
        });

        // Translate placeholders
        document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
            const val = this.t(el.getAttribute('data-i18n-placeholder'));
            if (val !== el.getAttribute('data-i18n-placeholder')) el.placeholder = val;
        });

        // Translate title attributes
        document.querySelectorAll('[data-i18n-title]').forEach(el => {
            const val = this.t(el.getAttribute('data-i18n-title'));
            if (val !== el.getAttribute('data-i18n-title')) el.title = val;
        });

        // Update language selector button
        const btn = document.querySelector('.language-selector');
        if (btn) btn.textContent = this.langNames[this.currentLang] || this.currentLang;

        // Dispatch event for components that need to react
        document.dispatchEvent(new CustomEvent('languageChanged', { detail: { lang: this.currentLang } }));
    }

    // Render a language selector menu (call from any page)
    renderSelector(containerId) {
        const container = document.getElementById(containerId);
        if (!container) return;
        container.innerHTML = this.supportedLangs.map(lang =>
            `<a href="#" onclick="event.preventDefault();i18n.load('${lang}')"
                style="${lang === this.currentLang ? 'font-weight:700;color:#2e7d32' : ''}">${this.langNames[lang]}</a>`
        ).join('');
    }

    // Wait for translations to be ready
    async ready() {
        return this._ready;
    }
}

window.i18n = new I18n();
