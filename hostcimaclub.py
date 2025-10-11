# -*- coding: utf-8 -*-
###################################################
# CimaClub - e2iplayer host
# Updated: 11/10/2025
###################################################
from Plugins.Extensions.IPTVPlayer.components.ihost import CHostBase, CBaseHostClass
from Plugins.Extensions.IPTVPlayer.libs.pCommon import CParsingHelper
from Plugins.Extensions.IPTVPlayer.tools.iptvtools import printDBG, printExc
from Plugins.Extensions.IPTVPlayer.tools.iptvtypes import strwithmeta
import re, urllib
from Components.config import config

class CimaClub(CBaseHostClass):

    def __init__(self):
        CBaseHostClass.__init__(self, {'history': 'cimaclub', 'cookie': 'cimaclub.cookie'})
        self.MAIN_URL = 'https://ciimaclub.club'
        self.SEARCH_URL = self.MAIN_URL + '/search'
        self.DEFAULT_ICON_URL = "https://raw.githubusercontent.com/oe-mirrors/e2iplayer/gh-pages/Thumbnails/cimaclub.png"
        self.AJAX_URL = self.MAIN_URL + '/wp-content/themes/CimaClub/ajaxCenter/Home/AdvFiltering.php'

        self.HEADER = self.cm.getDefaultHeader(browser='chrome')
        self.defaultParams = {
            'header': self.HEADER,
            'use_cookie': True,
            'load_cookie': True,
            'save_cookie': True,
            'cookiefile': self.COOKIE_FILE
        }

    def getPage(self, baseUrl, addParams=None, post_data=None):
        if addParams is None:
            addParams = dict(self.defaultParams)
        addParams["cloudflare_params"] = {"cookie_file": self.COOKIE_FILE, "User-Agent": self.HEADER.get("User-Agent")}
        return self.cm.getPageCFProtection(baseUrl, addParams, post_data)

    ###################################################
    # MAIN MENU
    ###################################################
    def listMainMenu(self, cItem):
        printDBG('CimaClub.listMainMenu')
        MAIN_CAT_TAB = [
            {'category': 'list_categories', 'title': _('الرئيسية'), 'url': self.MAIN_URL},
            {'category': 'search', 'title': _('بحث'), 'search_item': True},
        ]
        self.listsTab(MAIN_CAT_TAB, cItem)

    ###################################################
    # LIST CATEGORIES
    ###################################################
    def listCategories(self, cItem):
        printDBG('CimaClub.listCategories')

        sts, data = self.getPage(self.MAIN_URL)
        if not sts:
            return

        # Get only the dropdown section
        data = self.cm.ph.getDataBeetwenMarkers(data, '<div class="dropdown select-menu">', '</div>', False)[1]
        if not data:
            printDBG('No dropdown menu found')
            return

        # Extract all category <li> blocks
        cat_blocks = self.cm.ph.getAllItemsBeetwenMarkers(data, '<li', '</li>')
        printDBG('Found %d categories' % len(cat_blocks))

        for item in cat_blocks:
            cat_id = self.cm.ph.getSearchGroups(item, r'data-cat="([^"]+)"')[0]
            cat_name = self.cleanHtmlStr(self.cm.ph.getDataBeetwenMarkers(item, '<span', '</span>')[1])
            if not cat_name or cat_name == '.':
                continue

            params = dict(cItem)
            params.update({
                'category': 'list_items',
                'title': cat_name,
                'cat_id': cat_id
            })
            self.addDir(params)

    ###################################################
    # LIST ITEMS FROM CATEGORY (AJAX POST)
    ###################################################
    def listItems(self, cItem):
        printDBG('CimaClub.listItems >>> %s' % cItem)
        cat_id = cItem.get('cat_id', '')
        if not cat_id:
            return

        post_data = {'category': cat_id}
        sts, data = self.getPage(self.AJAX_URL, post_data=post_data)
        if not sts:
            return

        # Extract each movie box cleanly
        blocks = self.cm.ph.getAllItemsBeetwenMarkers(data, '<div class="Small--Box">', '</div>')
        printDBG('Found %d items' % len(blocks))

        for block in blocks:
            url = self.cm.ph.getSearchGroups(block, r'href="([^"]+)"')[0]
            icon = self.cm.ph.getSearchGroups(block, r'data-src="([^"]+)"')[0]
            if not icon:
                icon = self.cm.ph.getSearchGroups(block, r'src="([^"]+)"')[0]

            title = self.cleanHtmlStr(self.cm.ph.getSearchGroups(block, r'title="([^"]+)"')[0])
            desc = self.cleanHtmlStr(self.cm.ph.getDataBeetwenMarkers(block, '<p>', '</p>', False)[1])
            quality = self.cleanHtmlStr(self.cm.ph.getDataBeetwenMarkers(block, '<span style=', '</span>', False)[1])

            params = dict(cItem)
            params.update({
                'title': title,
                'url': self.getFullUrl(url),
                'icon': self.getFullUrl(icon),
                'desc': '%s | %s' % (quality, desc),
                'category': 'explore_items'
            })
            self.addDir(params)

    ###################################################
    # EXPLORE ITEM (get list of servers)
    ###################################################
    def exploreItems(self, cItem):
        printDBG('CiimaClub.exploreItems >>> %s' % cItem)

        url = cItem['url']
        # Add "watch/" to the movie page URL
        if not url.endswith('/'):
            url += '/'
        url += 'watch/'

        sts, data = self.getPage(url)
        if not sts:
            return

        # Extract the main <ul id="watch"> section
        watch_list = self.cm.ph.getDataBeetwenMarkers(data, '<ul id="watch">', '</ul>', False)[1]
        if not watch_list:
            printDBG('No watch list found')
            return

        # Get all <li> blocks between markers
        li_items = self.cm.ph.getAllItemsBeetwenMarkers(watch_list, '<li', '</li>')
        printDBG('Found %d servers' % len(li_items))

        for item in li_items:
            # Extract server name and URL
            url = self.cm.ph.getSearchGroups(item, r'data-watch="([^"]+)"')[0]
            title = self.cm.ph.getSearchGroups(item, r'>([^<]+)</noscript>')[0].strip()

            if not url:
                continue

            # Clean up title (e.g. remove numbers like <span>0</span>)
            title = self.cm.ph.clean_html(title)
            if not title:
                title = self.cm.ph.getSearchGroups(item, r'>([^<]+)</span>')[0].strip()

            params = dict(cItem)
            params.update({
                'title': title,
                'url': url,
                'category': 'video',
                'type': 'video',
            })
            self.addVideo(params)

        if len(li_items) == 0:
            printDBG('No <li> items found in <ul id="watch">')


    ###################################################
    # GET LINKS FOR VIDEO
    ###################################################
    def getLinksForVideo(self, cItem):
        printDBG('CimaClub.getLinksForVideo [%s]' % cItem)
        url = cItem.get('url', '')
        if not url:
            return []
        return [{'name': 'CimaClub - %s' % cItem.get('title', ''), 'url': url, 'need_resolve': 1}]

    ###################################################
    # SEARCH
    ###################################################
    def listSearchResult(self, cItem, searchPattern, searchType):
        printDBG("CimaClub.listSearchResult searchPattern[%s] searchType[%s]" % (searchPattern, searchType))
        post_data = {'search': searchPattern}
        sts, data = self.getPage(self.SEARCH_URL, post_data=post_data)
        if not sts:
            return

        results = re.findall(r'<a href="([^"]+)" title="([^"]+)" class="recent--block".*?data-src="([^"]+)"', data, re.S)
        for (url, title, icon) in results:
            params = dict(cItem)
            params.update({
                'title': self.cleanHtmlStr(title),
                'url': self.getFullUrl(url),
                'icon': self.getFullUrl(icon),
                'category': 'explore_items'
            })
            self.addDir(params)


    def handleService(self, index, refresh=0, searchPattern='', searchType=''):
        printDBG('CimaClub.handleService start')

        CBaseHostClass.handleService(self, index, refresh, searchPattern, searchType)

        name = self.currItem.get("name", '')
        category = self.currItem.get("category", '')

        printDBG("handleService: >> name[%s], category[%s] " % (name, category))
        self.currList = []

        # MAIN MENU
        if name is None:
            self.listMainMenu({'name': 'category'})
        elif category == 'list_categories':
            self.listCategories(cItem)
        elif category == 'list_items':
            self.listItems(cItem)
        elif category == 'explore_items':
            self.exploreItems(cItem)
        elif category == 'search':
            self.listSearchResult(cItem, cItem.get('search_pattern', ''), cItem.get('search_type', ''))

        # SEARCH
        elif category in ["search", "search_next_page"]:
            cItem = dict(self.currItem)
            cItem.update({'search_item': False, 'name': 'category'})
            self.listSearchResult(cItem, searchPattern, searchType)
        # HISTORY SEARCH
        elif category == "search_history":
            self.listsHistory({'name': 'history', 'category': 'search'}, 'desc', _("Type: "))
        else:
            printExc()

        CBaseHostClass.endHandleService(self, index, refresh)

class IPTVHost(CHostBase):

    def __init__(self):
        CHostBase.__init__(self, CimaClub(), True, [])

    def withArticleContent(self, cItem):
        if 'video' == cItem.get('type', '') or 'explore_item' == cItem.get('category', ''):
            return True
        return False
