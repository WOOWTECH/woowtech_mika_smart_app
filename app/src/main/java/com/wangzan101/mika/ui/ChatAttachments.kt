package com.wangzan101.mika.ui

import com.wangzan101.mika.R
import com.wangzan101.mika.i18n.tr
import androidx.compose.ui.res.stringResource
import android.content.ActivityNotFoundException
import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wangzan101.mika.ui.components.cardSurface
import com.wangzan101.mika.ui.theme.MikaColors
import com.wangzan101.mika.ui.theme.MikaIcons
import com.wangzan101.mika.ui.theme.MikaTheme

/** 对话页附件的说法。 */
object AttachCopy {
    val ADD: String get() = tr(R.string.attach_add)
    val CLOSE: String get() = tr(R.string.attach_close)
    val CAMERA: String get() = tr(R.string.attach_camera)
    val ALBUM: String get() = tr(R.string.attach_album)
    val FILES: String get() = tr(R.string.attach_files)
    val NO_CAMERA: String get() = tr(R.string.attach_no_camera)
    val GONE: String get() = tr(R.string.attach_gone)
    val IMPORTING: String get() = tr(R.string.attach_importing)

    fun remove(name: String) = tr(R.string.attach_remove, name)
    fun overLimit(n: Int) = tr(R.string.attach_over_limit, AttachTray.LIMIT, n)
}

// ---------- 面板 ----------

/**
 * 「＋」点开的面板里那一份活:系统相机、照片选择器、文件选择器。
 * 选中的内容地址交给 [onPicked]。
 */
@Suppress("UNUSED_PARAMETER")
@Composable
internal fun AttachPanelHost(
    selected: List<PendingAttachment>,
    onPicked: (List<String>) -> Unit,
    onToggle: (PendingAttachment) -> Boolean,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    var cameraUri by rememberSaveable { mutableStateOf<String?>(null) }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val uri = cameraUri ?: return@rememberLauncherForActivityResult
        cameraUri = null
        if (ok) onPicked(listOf(uri)) else AttachFiles.discardCamera(context, Uri.parse(uri))
    }
    val album = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(AttachTray.LIMIT)) { uris ->
        onPicked(uris.map { it.toString() })
    }
    val files = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        onPicked(uris.map { it.toString() })
    }
    val openAlbum = { album.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
    AttachPanel(
        onCamera = {
            val uri = AttachFiles.newCameraUri(context)
            cameraUri = uri.toString()
            try { camera.launch(uri) } catch (e: ActivityNotFoundException) {
                cameraUri = null
                AttachFiles.discardCamera(context, uri)
                Toast.makeText(context, AttachCopy.NO_CAMERA, Toast.LENGTH_SHORT).show()
            }
        },
        onAlbum = openAlbum,
        onFiles = { files.launch(arrayOf("*/*")) },
        modifier = modifier,
    )
}

/**
 * 面板:系统相机、照片选择器和文件选择器。
 */
@Composable
internal fun AttachPanel(
    onCamera: () -> Unit,
    onAlbum: () -> Unit,
    onFiles: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxSize().testTag("attach-panel").padding(start = 12.dp, end = 12.dp, top = 12.dp, bottom = 8.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Tile(MikaIcons.PhotoCamera, AttachCopy.CAMERA, onCamera)
            Tile(MikaIcons.Photo, AttachCopy.ALBUM, onAlbum)
            Tile(MikaIcons.Paperclip, AttachCopy.FILES, onFiles)
        }
    }
}

@Composable
private fun RowScope.Tile(icon: ImageVector, label: String, onClick: () -> Unit) {
    val c = MikaTheme.colors
    Column(
        Modifier.weight(1f).height(76.dp).cardSurface(c, TileShape).clip(TileShape).clickable(role = Role.Button, onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically),
    ) {
        Icon(icon, null, Modifier.size(24.dp), tint = c.ink)
        Text(label, style = TileText, color = c.ink)
    }
}

// ---------- 待发 ----------

/** 输入框上方一排待发的附件:照片是方块缩略图,文件是小卡片(类型、名字、大小),右上角 × 去掉。 */
@Composable
internal fun PendingTray(items: List<PendingAttachment>, onRemove: (String) -> Unit, modifier: Modifier = Modifier) {
    val c = MikaTheme.colors
    Row(
        modifier.fillMaxWidth().testTag("attach-tray").horizontalScroll(rememberScrollState()).padding(start = 4.dp, end = 10.dp, top = 8.dp, bottom = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        for (a in items) {
            Box {
                if (a.photo) {
                    val thumb = rememberAttachImage(AttachImage.Picked(a.uri), TRAY_PX)
                    Box(Modifier.testTag("tray-photo").size(58.dp).clip(ChipShape).background(c.fill)) {
                        thumb?.let { Image(it, a.name, Modifier.matchParentSize(), contentScale = ContentScale.Crop) }
                    }
                } else {
                    Row(
                        Modifier.testTag("tray-file").height(58.dp).widthIn(max = 200.dp).cardSurface(c, ChipShape).padding(horizontal = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        TypeBadge(a.name, Modifier.size(28.dp, 34.dp), small = true)
                        Column(Modifier.widthIn(max = 130.dp)) {
                            Text(a.name, style = ChipName, color = c.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(ChatViewModel.sizeLabel(a.size), style = ChipMeta, color = c.ink3, maxLines = 1)
                        }
                    }
                }
                Box(
                    Modifier.align(Alignment.TopEnd).offset(6.dp, (-6).dp).size(20.dp).clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.65f))
                        .clickable(role = Role.Button, onClickLabel = AttachCopy.remove(a.name)) { onRemove(a.uri) }
                        .semantics { contentDescription = AttachCopy.remove(a.name) },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(MikaIcons.Close, null, Modifier.size(12.dp), tint = Color.White)
                }
            }
        }
    }
}

// ---------- 发出去的 ----------

/**
 * 用户消息里带的附件:照片排成格子(见 [PhotoGrid];1 张保持比例,2 张并排,3 张起三列),文件是卡片(类型、名字、大小);
 * 点照片或卡片交给 [onOpen](在 App 里的查看页打开)。最宽 [maxWidth]。
 */
@Composable
internal fun SentAttachments(parsed: AttachmentMessage.Parsed, conversationId: String?, maxWidth: Dp, onOpen: (AttachmentMessage.Item) -> Unit) {
    Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (parsed.photos.isNotEmpty()) SentPhotos(parsed.photos, conversationId, maxWidth, onOpen)
        for (f in parsed.files) SentFileCard(f, maxWidth) { onOpen(f) }
    }
}

@Composable
private fun SentPhotos(photos: List<AttachmentMessage.Item>, conversationId: String?, maxWidth: Dp, onOpen: (AttachmentMessage.Item) -> Unit) {
    val c = MikaTheme.colors
    val cols = PhotoGrid.columns(photos.size)
    if (cols == 1) {
        val p = photos.single()
        val thumb = conversationId?.let { rememberAttachImage(AttachImage.Sent(it, p.path), SINGLE_PX) }
        val ratio = thumb?.let { (it.width.toFloat() / it.height.coerceAtLeast(1)).coerceIn(0.56f, 1.8f) } ?: 0.75f
        Box(
            Modifier.testTag("sent-photo").width(minOf(SingleWidth, maxWidth)).aspectRatio(ratio).clip(GridPhotoShape).background(c.fill)
                .clickable(role = Role.Image, onClickLabel = stringResource(R.string.attach_view_large)) { onOpen(p) },
        ) {
            thumb?.let { Image(it, p.name, Modifier.matchParentSize(), contentScale = ContentScale.Crop) }
        }
        return
    }
    val gap = 4.dp
    val cell = minOf(if (cols == 2) 118.dp else 96.dp, (maxWidth - gap * (cols - 1)) / cols)
    val px = with(LocalDensity.current) { cell.roundToPx() }.coerceAtLeast(64)
    Column(Modifier.clip(GridPhotoShape), verticalArrangement = Arrangement.spacedBy(gap)) {
        photos.chunked(cols).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                row.forEach { p ->
                    val thumb = conversationId?.let { rememberAttachImage(AttachImage.Sent(it, p.path), px) }
                    Box(
                        Modifier.testTag("sent-photo").size(cell).background(c.fill)
                            .clickable(role = Role.Image, onClickLabel = stringResource(R.string.attach_view_large)) { onOpen(p) },
                    ) {
                        thumb?.let { Image(it, p.name, Modifier.matchParentSize(), contentScale = ContentScale.Crop) }
                    }
                }
            }
        }
    }
}

@Composable
private fun SentFileCard(f: AttachmentMessage.Item, maxWidth: Dp, onClick: () -> Unit) {
    val c = MikaTheme.colors
    Row(
        Modifier.testTag("sent-file").widthIn(min = minOf(220.dp, maxWidth), max = maxWidth).cardSurface(c, FileCardShape).clip(FileCardShape)
            .clickable(onClickLabel = stringResource(R.string.chat_open), role = Role.Button, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        TypeBadge(f.name, Modifier.size(38.dp, 44.dp), small = false)
        Column(Modifier.weight(1f, fill = false)) {
            Text(f.name, style = FileCardName, color = c.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(f.size, style = ChipMeta, color = c.ink3, maxLines = 1)
        }
    }
}

/** 文件类型角标:按扩展名配色,上面写扩展名。 */
@Composable
private fun TypeBadge(name: String, modifier: Modifier, small: Boolean) {
    val shape = RoundedCornerShape(if (small) 5.dp else 7.dp)
    Box(modifier.background(badgeColor(FileBadge.kind(name), MikaTheme.colors), shape), contentAlignment = Alignment.Center) {
        Text(FileBadge.text(name), style = if (small) BadgeSmall else BadgeLarge, color = Color.White, maxLines = 1)
    }
}

private fun badgeColor(kind: FileBadge.Kind, c: MikaColors): Color = when (kind) {
    FileBadge.Kind.Pdf -> c.bad
    FileBadge.Kind.Sheet -> c.ok
    FileBadge.Kind.Doc -> c.accent
    FileBadge.Kind.Slides -> c.warnSolid
    FileBadge.Kind.Archive, FileBadge.Kind.Other -> NeutralBadge
}

/** 缩略图解到这么大(像素):面板格子、待发的小方块、单张大图。 */
private const val TRAY_PX = 180
private const val SINGLE_PX = 640

private val SingleWidth = 200.dp
private val NeutralBadge = Color(0xFF8E8E93)
private val TileShape = RoundedCornerShape(16.dp)
private val ChipShape = RoundedCornerShape(12.dp)
private val GridPhotoShape = RoundedCornerShape(14.dp)
private val FileCardShape = RoundedCornerShape(14.dp)
private val TileText = TextStyle(fontSize = 12.5.sp, lineHeight = 16.sp)
private val BadgeSmall = TextStyle(fontSize = 8.5.sp, lineHeight = 10.sp, fontWeight = FontWeight.Bold)
private val BadgeLarge = TextStyle(fontSize = 10.5.sp, lineHeight = 12.sp, fontWeight = FontWeight.Bold)
private val ChipName = TextStyle(fontSize = 12.5.sp, lineHeight = 16.sp, fontWeight = FontWeight.Medium)
private val ChipMeta = TextStyle(fontSize = 11.5.sp, lineHeight = 15.sp)
private val FileCardName = TextStyle(fontSize = 14.sp, lineHeight = 19.sp, fontWeight = FontWeight.Medium)
