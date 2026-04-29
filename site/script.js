const LINKS = {
  windows: "https://github.com/esa1992/to_do_list/releases/latest",
  macos: "https://github.com/esa1992/to_do_list/releases/latest",
  android: "https://github.com/esa1992/to_do_list/releases/latest",
  iosTestFlight: ""
};

const RELEASES_API = "https://api.github.com/repos/esa1992/to_do_list/releases/latest";

document.getElementById("year").textContent = String(new Date().getFullYear());

const win = document.getElementById("win-link");
const mac = document.getElementById("mac-link");
const android = document.getElementById("android-link");
const ios = document.getElementById("ios-link");
const releaseInfo = document.getElementById("release-info");

win.href = LINKS.windows;
mac.href = LINKS.macos;
android.href = LINKS.android;

if (LINKS.iosTestFlight) {
  ios.classList.remove("disabled");
  ios.removeAttribute("aria-disabled");
  ios.href = LINKS.iosTestFlight;
  ios.querySelector("span").textContent = "TestFlight";
}

function disableDownload(link, message) {
  link.classList.add("disabled");
  link.setAttribute("aria-disabled", "true");
  link.removeAttribute("href");
  link.querySelector("span").textContent = message;
}

function enableDownload(link, url) {
  link.classList.remove("disabled");
  link.removeAttribute("aria-disabled");
  link.href = url;
}

function findAssetUrl(assets, platform) {
  const patterns = {
    windows: [/portable.*win.*zip/i, /win.*portable.*zip/i, /windows.*zip/i],
    macos: [/macos.*zip/i, /mac.*zip/i],
    android: [/\.apk$/i, /android/i]
  };
  const platformPatterns = patterns[platform] || [];
  for (const regex of platformPatterns) {
    const found = assets.find((asset) => regex.test(asset.name || ""));
    if (found?.browser_download_url) return found.browser_download_url;
  }
  return null;
}

async function hydrateReleaseLinks() {
  try {
    const response = await fetch(RELEASES_API, {
      headers: { Accept: "application/vnd.github+json" }
    });
    if (!response.ok) throw new Error(`GitHub API error: ${response.status}`);

    const release = await response.json();
    const assets = Array.isArray(release.assets) ? release.assets : [];

    const windowsAsset = findAssetUrl(assets, "windows");
    const macAsset = findAssetUrl(assets, "macos");
    const androidAsset = findAssetUrl(assets, "android");

    if (windowsAsset) {
      enableDownload(win, windowsAsset);
    } else {
      disableDownload(win, "Файл появится в Release");
    }

    if (macAsset) {
      enableDownload(mac, macAsset);
    } else {
      disableDownload(mac, "Файл появится в Release");
    }

    if (androidAsset) {
      enableDownload(android, androidAsset);
    } else {
      disableDownload(android, "Файл появится в Release");
    }

    const releaseName = release.name || release.tag_name || "последнего релиза";
    releaseInfo.textContent = `Ссылки обновлены из ${releaseName}.`;
  } catch (_err) {
    disableDownload(win, "Release ещё не опубликован");
    disableDownload(mac, "Release ещё не опубликован");
    disableDownload(android, "Release ещё не опубликован");
    releaseInfo.textContent = "Release с файлами ещё не опубликован. После выпуска версии ссылки появятся автоматически.";
  }
}

hydrateReleaseLinks();
