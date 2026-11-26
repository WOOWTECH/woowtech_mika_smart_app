package com.wangzan101.mika.woowbot

/** Explicit local build opt-in only; never exposes a JavaScript interface or remote debugging. */
internal object BotViewportDiagnostics {
    val script = """
        JSON.stringify((function() {
          function box(e) {
            if (!e) return null;
            const r=e.getBoundingClientRect(),s=getComputedStyle(e);
            return {tag:e.tagName,x:r.x,y:r.y,width:r.width,height:r.height,bottom:r.bottom,
              clientHeight:e.clientHeight,scrollHeight:e.scrollHeight,cssHeight:s.height,
              minHeight:s.minHeight,maxHeight:s.maxHeight,display:s.display,position:s.position,
              overflowY:s.overflowY,boxSizing:s.boxSizing,flex:s.flex,
              paddingTop:s.paddingTop,paddingBottom:s.paddingBottom};
          }
          const composer=document.querySelector('[data-look="composer"]')||document.querySelector('textarea,[contenteditable="true"]');
          const ancestors=[];
          for(let e=composer;e&&ancestors.length<10;e=e.parentElement)ancestors.push(box(e));
          const vv=window.visualViewport;
          return {inner:{width:innerWidth,height:innerHeight},visualViewport:vv?{width:vv.width,height:vv.height,scale:vv.scale,offsetTop:vv.offsetTop}:null,
            devicePixelRatio,html:box(document.documentElement),body:box(document.body),root:box(document.getElementById('root')),app:box(document.querySelector('[data-look="app"]')),
            composerAncestors:ancestors,features:{resizeObserver:typeof ResizeObserver!=='undefined',visualViewport:!!vv,displayContents:CSS.supports('display','contents'),flex:CSS.supports('display','flex'),desktopBridge:typeof window.ogb!=='undefined'}};
        })())
    """.trimIndent()
}
