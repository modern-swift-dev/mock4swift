# Contributing to Mocksmith

## Publishing the site

Maintainers publish the site as part of the release workflow:

1. Publish the GitHub release.
2. Run `make site-build`.
3. Review the generated release data and DocC changes in `docs/`.
4. Commit `docs/`.

The complete build fetches the latest non-draft, non-prerelease GitHub release, builds the Astro pages,
and generates the four static DocC sites. It replaces `docs/` and writes `docs/.nojekyll`.

Before the first publication, configure the repository's Pages source to the `main` branch and `/docs`
folder in GitHub's [branch publishing configuration](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site).
The build does not change that remote Pages setting.
