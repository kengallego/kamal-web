# README images

These images show the real Kamal Web interface with fictional projects, documentation-only IPs (`192.0.2.0/24`) and sample metrics and logs. No live infrastructure or credentials are shown. The screenshots use English at 80% browser zoom.

- `hero.webp`: README cover, composed from `hero.svg` and `dashboard.webp`.
- `hero.svg`: editable cover background, using the app's cube icon and theme colors. The empty lower frame is filled during export.
- `dashboard.webp`: light-mode dashboard, also the cover's click-through image.
- `monitoring.webp`: dark-mode monitoring view, cropped to the project content.
- `logs.webp`: dark-mode output from a completed example app-log command, cropped to the project content.

To rebuild the cover after editing its background, run these commands from the repository root. They require `rsvg-convert` (librsvg) and ImageMagick; generated intermediates stay in `/tmp`.

```sh
rsvg-convert docs/images/hero.svg -o /tmp/kamal-web-cover.png
magick docs/images/dashboard.webp -resize 1480x /tmp/kamal-web-dashboard.png
magick /tmp/kamal-web-cover.png /tmp/kamal-web-dashboard.png -geometry +60+304 -composite -quality 92 docs/images/hero.webp
```

When refreshing screenshots, use a separate local database with sample data. Keep production domains, repository URLs, credentials and secret status-board or webhook URLs out of the images. Export as WebP and keep the content readable when opened at full size.
