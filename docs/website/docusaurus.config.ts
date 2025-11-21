import { Config } from "@docusaurus/types";
import { themes as prismThemes } from "prism-react-renderer";

const config: Config = {
  title: "ReactiveViews",
  tagline: "Bring modern React islands to every Rails view.",
  favicon: "img/logo.svg",
  url: "https://elisoncampos.github.io",
  baseUrl: "/reactive_views/",
  organizationName: "elisoncampos",
  projectName: "reactive_views",
  deploymentBranch: "gh-pages",
  trailingSlash: false,
  onBrokenLinks: "throw",
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: "warn"
    }
  },
  i18n: {
    defaultLocale: "en",
    locales: [ "en" ]
  },
  presets: [
    [
      "classic",
      {
        docs: {
          sidebarPath: "./sidebars.ts",
          editUrl: "https://github.com/elisoncampos/reactive_views/edit/main/docs/website/"
        },
        blog: false,
        theme: {
          customCss: "./src/css/custom.css"
        }
      }
    ]
  ],
  themeConfig: {
    colorMode: {
      defaultMode: "light",
      disableSwitch: true,
      respectPrefersColorScheme: false
    },
    image: "img/logo.svg",
    navbar: {
      title: "ReactiveViews",
      logo: {
        alt: "ReactiveViews logo",
        src: "img/logo.svg"
      },
      items: [
        { type: "docSidebar", sidebarId: "defaultSidebar", position: "left", label: "Docs" },
        { href: "https://github.com/elisoncampos/reactive_views", label: "GitHub", position: "right" }
      ]
    },
    footer: {
      style: "light",
      links: [
        {
          title: "Guides",
          items: [
            { label: "Quickstart", to: "/docs/quickstart" },
            { label: "Caching", to: "/docs/caching" },
            { label: "SSR architecture", to: "/docs/ssr-architecture" }
          ]
        },
        {
          title: "Community",
          items: [
            { label: "GitHub Discussions", href: "https://github.com/elisoncampos/reactive_views/discussions" },
            { label: "Issues", href: "https://github.com/elisoncampos/reactive_views/issues" }
          ]
        }
      ],
      copyright: `© ${new Date().getFullYear()} ReactiveViews.`
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula
    }
  }
};

export default config;

