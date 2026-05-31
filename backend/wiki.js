const axios = require('axios');

/**
 * Fetch a summary, thumbnail, and URL from Wikipedia for a peak name.
 * Uses the Wikipedia REST API — free, no key, returns clean JSON.
 *
 * @param {string} peakName - Name of the peak to look up
 * @returns {Promise<{extract: string, thumbnail: string|null, url: string|null}|null>}
 */
async function getWikiSummary(peakName) {
  try {
    const encoded = encodeURIComponent(peakName.replace(/ /g, '_'));
    const r = await axios.get(
      `https://en.wikipedia.org/api/rest_v1/page/summary/${encoded}`,
      { timeout: 5000 }
    );

    return {
      extract: r.data.extract,
      thumbnail: r.data.thumbnail?.source || null,
      url: r.data.content_urls?.mobile?.page || null,
    };
  } catch (err) {
    console.warn('[wiki] Wikipedia lookup failed for:', peakName, err.message);
    return null;
  }
}

module.exports = { getWikiSummary };
