package com.wangzan101.mika.ui

import com.wangzan101.mika.R
import com.wangzan101.mika.i18n.tr
import com.wangzan101.mika.about.MikaLinks

/** 关于页的文字。 */
object AboutCopy {
    val TITLE: String get() = tr(R.string.settings_about)
    val TAGLINE: String get() = tr(R.string.about_tagline)
    const val BETA = "Beta"

    val FEEDBACK: String get() = tr(R.string.about_feedback)
    val FEEDBACK_SUB: String get() = tr(R.string.about_feedback_sub)
    val FEEDBACK_SHEET_SUB: String get() = tr(R.string.about_feedback_sheet_sub)
    val FEEDBACK_GITHUB: String get() = tr(R.string.about_feedback_github)
    val FEEDBACK_GITHUB_SUB: String get() = tr(R.string.about_feedback_github_sub)

    val DIAGNOSTICS: String get() = tr(R.string.diagnostics_copy)
    val DIAGNOSTICS_SUB: String get() = tr(R.string.diagnostics_copy_sub)
    val DIAGNOSTICS_TITLE: String get() = tr(R.string.diagnostics_title)
    val DIAGNOSTICS_NOTE: String get() = tr(R.string.diagnostics_note)
    val DIAGNOSTICS_COPY: String get() = tr(R.string.diagnostics_copy_button)
    val DIAGNOSTICS_SHARE: String get() = tr(R.string.diagnostics_share)
    val DIAGNOSTICS_COPIED: String get() = tr(R.string.diagnostics_copied)
    val DIAGNOSTICS_LOADING: String get() = tr(R.string.diagnostics_loading)

    val REPO: String get() = tr(R.string.about_repo)
    val REPO_SUB: String get() = tr(R.string.about_repo_sub, MikaLinks.REPO_LABEL)
    val GUIDE: String get() = tr(R.string.about_guide)
    val GUIDE_SUB: String get() = tr(R.string.about_guide_sub)

    val DATA_NOTE: String get() = tr(R.string.about_data_note)
    val LICENSE_LINK: String get() = tr(R.string.about_license_link)
    val AUTHOR: String get() = tr(R.string.about_author)
    val LICENSE_TITLE: String get() = tr(R.string.about_license_title)

    val NO_BROWSER: String get() = tr(R.string.about_no_browser)

    fun version(versionName: String): String = tr(R.string.about_version, versionName)

    fun buildLabel(build: String): String = tr(R.string.about_build, build)
}
