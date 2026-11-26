# shellcheck shell=bash
# SC2034 "appears unused" is a false positive for a define-only library.
# shellcheck disable=SC2034
HPP_WIN_USER_BODY='[A-Za-z]:(/|\\\\?)Users(/|\\\\?)[^\\$%<{~"[:space:]/]([^\\$%<{~"[:space:]/]|%[0-9])*(~[0-9]+)?'
HPP_MACOS_USER_BODY='/Users/[^\\$%<{~"[:space:]/]([^\\$%<{~"[:space:]/]|%[0-9])*'
HPP_LINUX_USER_BODY='/home/[^\\$%<{~"[:space:]/]([^\\$%<{~"[:space:]/]|%[0-9])*'
HPP_WIN_REPO_BODY='[A-Za-z]:(/|\\\\?)(repos|Repos|projects|Projects|dev|Dev)(/|\\\\?)[^\\$%<{~"[:space:]/]([^\\$%<{~"[:space:]/]|%[0-9])*(~[0-9]+)?'
HPP_ESCAPED_WIN_REPO_BODY='[A-Za-z]:\\\\(repos|Repos|projects|Projects|dev|Dev)\\\\[^\\$%<{~"[:space:]/]([^\\$%<{~"[:space:]/]|%[0-9])*(~[0-9]+)?'
