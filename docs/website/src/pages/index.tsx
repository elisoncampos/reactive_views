import Link from "@docusaurus/Link";
import Layout from "@theme/Layout";
import Heading from "@theme/Heading";
import React from "react";
import styles from "./index.module.css";

export default function Home(): JSX.Element {
  return (
    <Layout
      title="ReactiveViews"
      description="React islands for every Rails view"
    >
      <header className={styles.hero}>
        <div className={styles.heroContent}>
          <Heading as="h1">
            Build modern React islands without leaving Rails.
          </Heading>
          <p>
            ReactiveViews gives Rails teams a turnkey SSR pipeline, Vite-powered
            DX, and drop-in caching so you can ship interactive UIs from ERB in
            minutes.
          </p>
          <div className={styles.actions}>
            <Link className={styles.ctaPrimary} to="/docs/quickstart">
              Get started
            </Link>
            <Link
              className={styles.ctaSecondary}
              to="https://github.com/elisoncampos/reactive_views"
            >
              View on GitHub
            </Link>
          </div>
          <ul className={styles.featureList}>
            <li>SSR Node server with bundle caching</li>
            <li>Props inference + pluggable cache store</li>
            <li>Tree rendering for true React composition</li>
          </ul>
        </div>
      </header>
      <main className={styles.main}>
        <section className={styles.section}>
          <Heading as="h2">Why teams choose ReactiveViews</Heading>
          <div className={styles.grid}>
            <div>
              <h3>Rails-first workflow</h3>
              <p>
                Keep controllers, helpers, and layouts exactly where they are.
                Components live next to views, and generators wire up Vite +
                SSR for you.
              </p>
            </div>
            <div>
              <h3>Fast by default</h3>
              <p>
                Renderer + inference share the same cache store, while the Node
                server reuses esbuild bundles, so hot paths stay hot.
              </p>
            </div>
            <div>
              <h3>Junior friendly</h3>
              <p>
                Detailed docs, clear error overlays, and safe defaults mean new
                devs can ship components without touching Webpack configs.
              </p>
            </div>
          </div>
        </section>
      </main>
    </Layout>
  );
}

