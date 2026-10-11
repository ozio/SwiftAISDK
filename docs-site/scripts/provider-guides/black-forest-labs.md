## FLUX 3 image inputs

`flux-3-image` supports up to ten reference images, 768sq/1k/1.5k/2k/4k resolution, grounding, the latest version and safety tolerance 0–4. Size can derive an aspect ratio; explicit aspect ratio wins. Seed, masks and unsupported legacy fields warn and are omitted. Polling recognizes pending/reasoning/generating states and terminates on failed, moderated or missing tasks.

Official/signed external image downloads retain the versioned/custom user-agent while omitting provider authentication and request credentials. Same-origin custom proxies retain configured headers. Official polling remains authenticated. Image input capability discovery recognizes FLUX 3.
