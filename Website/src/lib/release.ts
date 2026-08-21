const latestReleaseURL =
  "https://api.github.com/repos/modern-swift-dev/mocksmith-swift/releases/latest";

export interface Release {
  version: string;
  installationVersion: string;
  publishedAt: Date;
  notesURL: string;
}

let releaseRequest: Promise<Release> | undefined;

function record(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function requiredString(
  value: Record<string, unknown>,
  key: string,
): string {
  const field = value[key];
  if (typeof field !== "string" || field.trim() === "") {
    throw new Error(`GitHub latest release response has no valid ${key}.`);
  }
  return field;
}

async function loadLatestRelease(): Promise<Release> {
  const token = import.meta.env.GITHUB_TOKEN;
  const headers: Record<string, string> = {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
  };
  if (typeof token === "string" && token.trim() !== "") {
    headers.Authorization = `Bearer ${token}`;
  }

  let response: Response;
  try {
    response = await fetch(latestReleaseURL, {
      headers,
    });
  } catch (error) {
    throw new Error(`Could not fetch the latest Mocksmith release: ${String(error)}`);
  }

  if (!response.ok) {
    throw new Error(
      `Could not fetch the latest Mocksmith release: GitHub returned ${response.status} ${response.statusText}.`,
    );
  }

  let value: unknown;
  try {
    value = await response.json();
  } catch (error) {
    throw new Error(
      `GitHub latest release response is not valid JSON: ${String(error)}`,
    );
  }
  if (!record(value)) {
    throw new Error("GitHub latest release response is not an object.");
  }
  if (value.draft !== false || value.prerelease !== false) {
    throw new Error("GitHub latest release is a draft or prerelease.");
  }

  const version = requiredString(value, "tag_name");
  const publishedAtValue = requiredString(value, "published_at");
  const notesURL = requiredString(value, "html_url");
  const publishedAt = new Date(publishedAtValue);

  if (Number.isNaN(publishedAt.getTime())) {
    throw new Error("GitHub latest release has an invalid published_at date.");
  }

  let parsedNotesURL: URL;
  try {
    parsedNotesURL = new URL(notesURL);
  } catch {
    throw new Error("GitHub latest release has an invalid html_url.");
  }
  if (
    parsedNotesURL.protocol !== "https:" ||
    parsedNotesURL.hostname !== "github.com" ||
    !parsedNotesURL.pathname.startsWith(
      "/modern-swift-dev/mocksmith-swift/releases/",
    )
  ) {
    throw new Error("GitHub latest release has an unexpected html_url.");
  }

  const installationVersion = version.replace(/^v/, "");
  if (!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(installationVersion)) {
    throw new Error("GitHub latest release tag is not a stable semantic version.");
  }

  return { version, installationVersion, publishedAt, notesURL };
}

export function fetchLatestRelease(): Promise<Release> {
  releaseRequest ??= loadLatestRelease();
  return releaseRequest;
}
