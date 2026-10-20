/**
 * Shapes shared across the extraction scripts: a platform's `platformConfig`
 * entry and the parsed course.json.
 */

/**
 * @typedef {Object} PlatformConfig
 * @property {string} [videoPlayerSelector]
 * @property {string} [loginUrl]
 * @property {string} [authEnvPrefix]
 * @property {string} [authProvider]
 * @property {number} [authWarnDays]
 * @property {string} [baseUrl]
 * @property {string} [courseSlug]
 * @property {string} [landingUrl]
 * @property {string} [landingUrlPattern]
 * @property {string} [referer]
 * @property {string} [subtitleLanguage]
 * @property {number} [manifestTimeoutMs]
 * @property {Record<string, unknown>} [frameExtraction]
 * @property {unknown[]} [resourceButtons]
 * @property {unknown} [resourceSelectors]
 * @property {string[]} [skipLessonTitles]
 */

/**
 * @typedef {Object} CourseLesson
 * @property {number} position
 * @property {string} title
 * @property {string} slug
 * @property {string} duration
 * @property {string} [status]
 * @property {boolean} [hasTranscript]
 * @property {boolean} [hasScreenshots]
 * @property {boolean} [hasDownload]
 * @property {boolean} [hasVideo]
 */

/**
 * @typedef {Object} CourseModule
 * @property {number} position
 * @property {string} title
 * @property {string} slug
 * @property {CourseLesson[]} lessons
 */

/**
 * @typedef {Object} Course
 * @property {string} [url]
 * @property {string} [title]
 * @property {string} [instructor]
 * @property {string} [platform]
 * @property {string} [duration]
 * @property {number} [totalLessons]
 * @property {string} [status]
 * @property {{ datePublished?: string | null }} [metadata]
 * @property {CourseModule[]} modules
 */

export {};
