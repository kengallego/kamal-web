module Ui
  class LanguageSwitcherComponent < ViewComponent::Base
    LABELS = {
      en: "English", es: "Español", de: "Deutsch", fr: "Français", "pt-BR": "Português (Brasil)",
      it: "Italiano", ja: "日本語", "zh-CN": "简体中文"
    }.freeze

    # Inline SVG, since flag emoji render as letters on Windows.
    FLAGS = {
      en: <<~SVG,
        <svg preserveAspectRatio="xMidYMid slice" viewBox="0 0 60 30" aria-hidden="true"><clipPath id="flag-gb-t"><path d="M30 15h30v15zv15H0zH0V0zV0h30z"/></clipPath><path d="M0 0v30h60V0z" fill="#012169"/><path d="M0 0l60 30m0-30L0 30" stroke="#fff" stroke-width="6"/><path d="M0 0l60 30m0-30L0 30" clip-path="url(#flag-gb-t)" stroke="#C8102E" stroke-width="4"/><path d="M30 0v30M0 15h60" stroke="#fff" stroke-width="10"/><path d="M30 0v30M0 15h60" stroke="#C8102E" stroke-width="6"/></svg>
      SVG
      es: <<~SVG,
        <svg preserveAspectRatio="xMidYMid slice" viewBox="0 0 60 30" aria-hidden="true"><path d="M0 0h60v30H0z" fill="#AA151B"/><path d="M0 7.5h60v15H0z" fill="#F1BF00"/></svg>
      SVG
      de: <<~SVG,
        <svg preserveAspectRatio="xMidYMid slice" viewBox="0 0 5 3" aria-hidden="true"><path d="M0 0h5v1H0z"/><path d="M0 1h5v1H0z" fill="#D00"/><path d="M0 2h5v1H0z" fill="#FFCE00"/></svg>
      SVG
      fr: <<~SVG,
        <svg preserveAspectRatio="xMidYMid slice" viewBox="0 0 3 2" aria-hidden="true"><path d="M0 0h1v2H0z" fill="#002654"/><path d="M1 0h1v2H1z" fill="#fff"/><path d="M2 0h1v2H2z" fill="#CE1126"/></svg>
      SVG
      "pt-BR": <<~SVG,
        <svg preserveAspectRatio="xMidYMid slice" viewBox="0 0 20 14" aria-hidden="true"><path d="M0 0h20v14H0z" fill="#009C3B"/><path d="M10 1.7 18.3 7 10 12.3 1.7 7z" fill="#FFDF00"/><circle cx="10" cy="7" r="3.5" fill="#002776"/><path d="M6.6 6.3a10 10 0 0 1 6.8 1.6" stroke="#fff" stroke-width=".6" fill="none"/></svg>
      SVG
      it: <<~SVG,
        <svg preserveAspectRatio="xMidYMid slice" viewBox="0 0 3 2" aria-hidden="true"><path d="M0 0h1v2H0z" fill="#009246"/><path d="M1 0h1v2H1z" fill="#fff"/><path d="M2 0h1v2H2z" fill="#CE2B37"/></svg>
      SVG
      ja: <<~SVG,
        <svg preserveAspectRatio="xMidYMid slice" viewBox="0 0 3 2" aria-hidden="true"><path d="M0 0h3v2H0z" fill="#fff"/><circle cx="1.5" cy="1" r=".6" fill="#BC002D"/></svg>
      SVG
      "zh-CN": <<~SVG
        <svg preserveAspectRatio="xMidYMid slice" viewBox="0 0 30 20" aria-hidden="true"><path d="M0 0h30v20H0z" fill="#EE1C25"/><g fill="#FFFF00"><polygon points="5.00,2.00 5.67,4.07 7.85,4.07 6.09,5.35 6.76,7.43 5.00,6.15 3.24,7.43 3.91,5.35 2.15,4.07 4.33,4.07"/><polygon points="9.14,2.51 9.62,1.97 9.25,1.34 9.91,1.63 10.39,1.08 10.33,1.80 11.00,2.09 10.29,2.25 10.22,2.97 9.85,2.35"/><polygon points="11.01,4.14 11.66,3.82 11.56,3.10 12.07,3.62 12.72,3.30 12.38,3.95 12.88,4.47 12.17,4.34 11.83,4.99 11.73,4.27"/><polygon points="11.04,6.73 11.76,6.70 11.96,6.00 12.21,6.68 12.94,6.66 12.37,7.10 12.62,7.79 12.01,7.38 11.44,7.83 11.64,7.13"/><polygon points="9.22,8.38 9.90,8.63 10.35,8.06 10.32,8.79 11.00,9.05 10.30,9.24 10.26,9.96 9.87,9.36 9.16,9.55 9.62,8.98"/></g></svg>
      SVG
    }.freeze

    def flag(locale)
      tag.span(FLAGS.fetch(locale).html_safe, class: "inline-flex h-3.5 w-5 shrink-0 overflow-hidden rounded-[3px] ring-1 ring-line [&>svg]:size-full [&>svg]:object-cover")
    end
  end
end
