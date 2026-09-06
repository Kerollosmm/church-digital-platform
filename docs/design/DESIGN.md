---
name: Coptic Heritage Digital
colors:
  surface: '#f7f9fb'
  surface-dim: '#d8dadc'
  surface-bright: '#f7f9fb'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f2f4f6'
  surface-container: '#eceef0'
  surface-container-high: '#e6e8ea'
  surface-container-highest: '#e0e3e5'
  on-surface: '#191c1e'
  on-surface-variant: '#45464d'
  inverse-surface: '#2d3133'
  inverse-on-surface: '#eff1f3'
  outline: '#76777d'
  outline-variant: '#c6c6cd'
  surface-tint: '#565e74'
  primary: '#000000'
  on-primary: '#ffffff'
  primary-container: '#131b2e'
  on-primary-container: '#7c839b'
  inverse-primary: '#bec6e0'
  secondary: '#904d00'
  on-secondary: '#ffffff'
  secondary-container: '#fe932c'
  on-secondary-container: '#663500'
  tertiary: '#000000'
  on-tertiary: '#ffffff'
  tertiary-container: '#331200'
  on-tertiary-container: '#cf6721'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#dae2fd'
  primary-fixed-dim: '#bec6e0'
  on-primary-fixed: '#131b2e'
  on-primary-fixed-variant: '#3f465c'
  secondary-fixed: '#ffdcc3'
  secondary-fixed-dim: '#ffb77d'
  on-secondary-fixed: '#2f1500'
  on-secondary-fixed-variant: '#6e3900'
  tertiary-fixed: '#ffdbca'
  tertiary-fixed-dim: '#ffb68e'
  on-tertiary-fixed: '#331200'
  on-tertiary-fixed-variant: '#763300'
  background: '#f7f9fb'
  on-background: '#191c1e'
  surface-variant: '#e0e3e5'
typography:
  display-lg:
    fontFamily: Cairo
    fontSize: 48px
    fontWeight: '700'
    lineHeight: 60px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Cairo
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
  headline-lg-mobile:
    fontFamily: Cairo
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 36px
  headline-md:
    fontFamily: Cairo
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  body-lg:
    fontFamily: Cairo
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: Cairo
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  label-md:
    fontFamily: Cairo
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.01em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 4px
  xs: 8px
  sm: 16px
  md: 24px
  lg: 40px
  xl: 64px
  gutter: 20px
  margin-mobile: 16px
  margin-desktop: 80px
---

## Brand & Style
The design system is rooted in the intersection of ancient spiritual heritage and contemporary digital refinement. It targets a global congregation, demanding a UI that feels both sacred and highly functional. 

The aesthetic is **Modern Glassmorphism** blended with **Minimalism**. It uses translucent layers to evoke a sense of light and transcendence, while maintaining strict grid discipline to ensure accessibility and trust. The emotional response should be one of peace, reverence, and premium quality, avoiding visual clutter to allow the spiritual content to breathe. High-quality whitespace and thin, intentional borders are used to define the visual structure.

## Colors
The palette is dominated by **Royal Navy**, providing a stable, trustworthy foundation. **Gold and Bronze** are used sparingly for interactive accents, iconography, and decorative flourishes that signify spiritual significance. 

- **Primary (Navy):** Used for headers, primary actions, and deep surface backgrounds.
- **Accent (Gold/Bronze):** Reserved for "Call to Action" buttons, active states, and symbolic icons.
- **Surface (Off-White/Slate):** The primary canvas is Off-White to ensure maximum legibility, while Slate is used for secondary containers and text contrast.
- **Functional:** Standardized across the system to ensure immediate recognition of system status without clashing with the spiritual aesthetic.

## Typography
This design system utilizes **Cairo** (integrated via the beVietnamPro slot for Latin fallbacks) to provide a modern, geometric Arabic typeface that maintains high legibility. 

The typography follows a **Right-to-Left (RTL)** orientation. Headlines should use heavier weights (Bold/Semi-Bold) to create a clear hierarchy. Body text is optimized for long-form reading of liturgical texts or articles, utilizing a generous line height (1.5x) to ensure comfort. All English/Latin characters should fall back to a clean sans-serif that mirrors the geometric properties of Cairo.

## Layout & Spacing
The layout follows a **Fluid Grid** model with a heavy emphasis on RTL flow. 

- **Desktop:** 12-column grid with 80px side margins to create a focused, "columnar" feel for text-heavy pages.
- **Mobile:** 4-column grid with 16px margins. 
- **Rhythm:** All spacing (padding/margins) must be multiples of 4px. Use `lg` and `xl` spacing to separate major sections, creating a "breathable" and calm user experience. 
- **Alignment:** All text and structural elements must be right-aligned by default. Icons should precede text in a right-to-left flow.

## Elevation & Depth
The design system employs **Glassmorphism** and **Tonal Layering** rather than traditional heavy shadows.

- **Level 1 (Base):** Off-white background (#F8FAFC).
- **Level 2 (Cards):** Pure white background with a very soft, diffused Navy-tinted shadow (0px 4px 20px rgba(15, 23, 42, 0.05)) and a 1px border (#E2E8F0).
- **Level 3 (Overlays/Glass):** Surfaces use a background blur (12px) with 80% opacity white fill. This is used for navigation bars and modal headers to maintain a sense of context.
- **Interactions:** Upon hover or active state, elements should transition with a subtle lift (increased shadow spread) or a slight color shift toward the Bronze accent.

## Shapes
Shapes are defined by **Rounded (0.5rem / 8px)** corners as the base, scaling up to **16px (rounded-lg)** for main content cards. 

This softened geometry balances the "institutional" feel of the Church with a modern, welcoming touch. Circles are used exclusively for user avatars and specific icon containers. Buttons use the base 8px roundedness to maintain a sturdy, professional appearance.

## Components
- **Buttons:** 
    - *Primary:* Navy background, White text. 
    - *Spiritual:* Gold background, Navy text (used for "Donate," "Join Prayer," etc.). 
    - *Ghost:* No fill, 1px Navy or Gold border. 
    - *Min-Height:* All buttons must be at least 48px to ensure touch-friendliness.
- **Cards:** 16px corner radius. Use for events, news, or sermons. Cards should feature a subtle 1px border.
- **Inputs:** RTL text entry is mandatory. Labels must be right-aligned above the field. Focus states use a 2px Gold border.
- **Chips/Badges:** Small, 4px rounded labels for categories (e.g., "Liturgy," "Youth," "Service") using light-tinted backgrounds of the primary color.
- **Iconography:** Use "Linear" style icons with a consistent 2px stroke. Incorporate the Coptic Cross as a recurring motif in headers or as a loading state indicator.
- **Lists:** Use dividers with 10% opacity Navy. Ensure the chevron (indicating drill-down) is mirrored for RTL (pointing left).