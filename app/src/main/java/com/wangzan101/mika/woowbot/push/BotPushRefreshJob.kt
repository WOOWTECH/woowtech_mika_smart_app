package com.wangzan101.mika.woowbot.push

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import kotlinx.coroutines.*

/** Durable unique work; Application must install the runtime before this service starts. */
class BotPushRefreshJob : JobService() {
    private var work: Job? = null
    override fun onStartJob(params: JobParameters): Boolean {
        work = CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            val complete = try { BotPushRuntime.controller?.refresh() ?: false }
            catch (e: CancellationException) { throw e }
            catch (_: Exception) { false }
            withContext(Dispatchers.Main) { jobFinished(params, !complete) }
        }
        return true
    }
    override fun onStopJob(params: JobParameters): Boolean {
        work?.cancel()
        return true
    }
    override fun onDestroy() {
        work?.cancel()
        super.onDestroy()
    }
    companion object {
        private const val ID = 0x574250
        fun schedule(context: Context): Boolean = context.getSystemService(JobScheduler::class.java).schedule(
            JobInfo.Builder(ID, ComponentName(context, BotPushRefreshJob::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPersisted(true)
                .setBackoffCriteria(30_000, JobInfo.BACKOFF_POLICY_EXPONENTIAL)
                .build()
        ) == JobScheduler.RESULT_SUCCESS
    }
}
