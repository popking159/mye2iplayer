# -*- coding: utf-8 -*-
###################################################
#  TorrentYTS Host for E2iPlayer (YTS + TorrServer)
#  Compatible with Python 2.7 / 3.x
#  Last modified: 28/10/2025 - popking (odem2014)
###################################################

# localization library
from Plugins.Extensions.IPTVPlayer.components.iptvplayerinit import TranslateTXT as _
# host main class
from Plugins.Extensions.IPTVPlayer.components.ihost import CHostBase, CBaseHostClass
# tools - write on log, write exception infos and merge dicts
from Plugins.Extensions.IPTVPlayer.tools.iptvtools import printDBG, printExc, MergeDicts, E2ColoR
# add metadata to url
from Plugins.Extensions.IPTVPlayer.tools.iptvtypes import strwithmeta
# library for json (instead of standard json.loads and json.dumps)
from Plugins.Extensions.IPTVPlayer.libs.e2ijson import loads as json_loads, dumps as json_dumps
# read informations in m3u8
from Plugins.Extensions.IPTVPlayer.libs.urlparserhelper import getDirectM3U8Playlist
###################################################
from Plugins.Extensions.IPTVPlayer.p2p3.UrlParse import urljoin
from Plugins.Extensions.IPTVPlayer.p2p3.UrlLib import urllib_quote_plus
from Components.config import config, ConfigSubsection, ConfigText
###################################################
# FOREIGN import
###################################################
import re
import time
import base64
import os
import subprocess
import socket

###################################################
# CONFIG SECTION
###################################################
config.plugins.iptvplayer.torserver = ConfigSubsection()
config.plugins.iptvplayer.torserver_ip = ConfigText(default="127.0.0.1", fixed_size=False)
config.plugins.iptvplayer.torserver_port = ConfigText(default="8090", fixed_size=False)
config.plugins.iptvplayer.torserver_api = ConfigText(default="", fixed_size=False)  # Changed default to empty
config.plugins.iptvplayer.torserver_path = ConfigText(default="/media/hdd/TorrServer", fixed_size=False)
config.plugins.iptvplayer.torserver_config = ConfigText(default="/media/hdd/config", fixed_size=False)

def GetConfigList():
    """Show TorServer config in E2iPlayer settings."""
    from Components.config import getConfigListEntry
    optionList = []
    optionList.append(getConfigListEntry(_("TorServer IP (default 127.0.0.1)"), config.plugins.iptvplayer.torserver_ip))
    optionList.append(getConfigListEntry(_("TorServer Port (default 8090)"), config.plugins.iptvplayer.torserver_port))
    optionList.append(getConfigListEntry(_("TorServer API path (usually empty)"), config.plugins.iptvplayer.torserver_api))  # Updated description
    optionList.append(getConfigListEntry(_("TorServer Binary Path"), config.plugins.iptvplayer.torserver_path))
    optionList.append(getConfigListEntry(_("TorServer Config Path"), config.plugins.iptvplayer.torserver_config))
    return optionList

def gettytul():
    return 'https://yts.mx/'  # main url of host

###################################################
# MAIN HOST CLASS
###################################################
class TorrentYTSHost(CBaseHostClass):

    def __init__(self):
        CBaseHostClass.__init__(self, {'history': 'yts.torrent', 'cookie': 'yts.cookie'})
        self.MAIN_URL = 'https://yts.mx'
        self.SEARCH_URL = self.MAIN_URL + '/browse-movies/'
        # --- TorrServer Configuration ---
        self.TORSERVER_PORT = 8090
        self.TORSERVER_IP = "127.0.0.1"
        self.TORSERVER_PATH = "/media/hdd/TorrServer"
        self.TORSERVER_CONFIG = "/media/hdd/config"
        self.DEFAULT_ICON_URL = 'https://raw.githubusercontent.com/popking159/mye2iplayer/refs/heads/main/torrentyts.jpg'
        self.updateTorServerUrl()

    def updateTorServerUrl(self):
        ip = config.plugins.iptvplayer.torserver_ip.value.strip()
        port = config.plugins.iptvplayer.torserver_port.value.strip()
        api = config.plugins.iptvplayer.torserver_api.value.strip()
        # Build base URL without API path for endpoints
        if api:
            self.TORSERVER_BASE = 'http://%s:%s/%s' % (ip, port, api.rstrip('/'))
        else:
            self.TORSERVER_BASE = 'http://%s:%s' % (ip, port)
        printDBG("TorServer base URL: %s" % self.TORSERVER_BASE)

    def isPortOpen(self, host, port, timeout=1.0):
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)
            result = sock.connect_ex((host, int(port)))
            sock.close()
            return result == 0
        except Exception as e:
            printDBG("isPortOpen error: %s" % str(e))
            return False

    def ensureTorServerRunning(self):
        """
        Ensure TorrServer is running and listening.
        If already running, restart cleanly.
        """
        port = int(config.plugins.iptvplayer.torserver_port.value.strip() or "8090")
        ip = config.plugins.iptvplayer.torserver_ip.value.strip() or "127.0.0.1"
        binary = config.plugins.iptvplayer.torserver_path.value.strip()
        config_path = config.plugins.iptvplayer.torserver_config.value.strip()

        # Check if config directory exists, create it if it doesn't
        if config_path and not os.path.exists(config_path):
            printDBG("Config directory does not exist, creating: %s" % config_path)
            try:
                os.makedirs(config_path, mode=0o755)  # Create directory with read/write/execute permissions for owner, read/execute for group/others
                printDBG("Successfully created config directory: %s" % config_path)
            except Exception as e:
                printDBG("Failed to create config directory %s: %s" % (config_path, str(e)))
                # Continue anyway, TorrServer might create it or use default locations

        # Check if port is already in use
        running = self.isPortOpen(ip, port)
        
        # If running, stop it first
        if running:
            printDBG("TorServer already running at %s:%s — restarting..." % (ip, port))
            try:
                shutdown_url = "http://%s:%s/shutdown" % (ip, port)
                self.cm.getPage(shutdown_url)
                time.sleep(2)
            except Exception as e:
                printDBG("Failed to shutdown old instance: %s" % e)

        # Start TorrServer fresh
        try:
            if binary and os.path.exists(binary):
                cmd = "%s -path %s -port %d > /dev/null 2>&1 &" % (binary, config_path, port)
                printDBG("Starting TorServer binary: %s" % cmd)
                os.system(cmd)
                time.sleep(4)
            else:
                printDBG("TorServer binary not found at: %s" % binary)
                return False
        except Exception as e:
            printDBG("Failed to start TorServer: %s" % e)
            return False

        # Verify it's up
        running = self.isPortOpen(ip, port, timeout=3.0)
        if running:
            printDBG("TorServer started successfully on %s:%d" % (ip, port))
        else:
            printDBG("TorServer failed to start on %s:%d" % (ip, port))
        return running

    ###################################################
    # LISTING
    ###################################################
    def listMainMenu(self, cItem):
        printDBG('TorrentYTSHost.listMainMenu')
        MAIN_CAT_TAB = [
            {'category': 'list_movies', 'title': _('Movies'), 'url': self.getFullUrl('/browse-movies')},
            {'category': 'list_movies', 'title': _('Trending'), 'url': self.getFullUrl('/trending-movies')},
            {'category': 'list_movies', 'title': _('4K'), 'url': self.getFullUrl('/browse-movies/0/2160p/all/0/latest/0/all')},
            {'category': 'list_movies', 'title': _('Horror'), 'url': self.getFullUrl('/browse-movies/0/all/horror/0/latest/0/all')},
            {'category': 'list_movies', 'title': _('Action'), 'url': self.getFullUrl('/browse-movies/0/all/action/0/latest/0/all')},
            {'category': 'list_movies', 'title': _('Comedy'), 'url': self.getFullUrl('/browse-movies/0/all/comedy/0/latest/0/all')},
            {'category': 'list_movies', 'title': _('Drama'), 'url': self.getFullUrl('/browse-movies/0/all/drama/0/latest/0/all')},
        ] + self.searchItems()
        self.listsTab(MAIN_CAT_TAB, cItem)

    ###################################################
    # LIST MOVIES
    ###################################################
    def listMovies(self, cItem):
        printDBG("TorrentYTSHost.listMovies url[%s]" % cItem.get('url', ''))
        sts, data = self.cm.getPage(cItem.get('url', ''))
        if not sts or not data:
            return

        try:
            main_block = self.cm.ph.getDataBeetwenMarkers(data, '<section', '</section>', False)[1]
        except Exception:
            main_block = data

        items = self.cm.ph.getAllItemsBeetwenMarkers(main_block, '<div class="browse-movie-wrap', '</div>', False)

        printDBG("Found %d movie items" % len(items))

        for item in items:
            try:
                # title from alt (may contain "(YEAR)" and "download")
                raw_title = self.cm.ph.getSearchGroups(item, r'alt="([^"]+)"')[0]
                if not raw_title:
                    continue
                raw_title = raw_title.replace('download', '').strip()

                # split into title and year if present
                match = re.search(r'(.+?)\s*\(?(\d{4})\)?$', raw_title)
                if match:
                    movie_title = match.group(1).strip()
                    movie_year = match.group(2).strip()
                else:
                    movie_title = raw_title
                    movie_year = ''

                # url & icon
                url = self.cm.ph.getSearchGroups(item, r'href="([^"]+)"')[0]
                icon = self.cm.ph.getSearchGroups(item, r'src="([^"]+)"')[0]

                # genres: h4 tags inside item (usually multiple <h4>Genre</h4>)
                genres = re.findall(r'<h4>([^<]+)</h4>', item)
                genre_str = ', '.join(genres) if genres else 'Unknown'

                # rating
                rating = self.cm.ph.getSearchGroups(item, r'<h4 class="rating">([^<]+)<')[0].strip()
                if not rating:
                    rating = 'N/A'

                # determine dynamic rating color
                try:
                    # rating format like "4.9 / 10" -> take left part
                    rating_left = rating.split('/')[0].strip()
                    rating_val = float(rating_left)
                    if rating_val >= 7.0:
                        rating_color_name = 'green'
                    elif rating_val >= 5.0:
                        rating_color_name = 'yellow'
                    else:
                        rating_color_name = 'red'
                except Exception:
                    rating_color_name = 'gray'

                # Colorized title: Title (Year)
                # Title in white, bracket in green, year in yellow, then reset to white
                if movie_year:
                    colored_title = (E2ColoR('white') + movie_title + ' ' +
                                     E2ColoR('green') + '(' +
                                     E2ColoR('yellow') + movie_year +
                                     E2ColoR('green') + ')' +
                                     E2ColoR('white'))
                else:
                    colored_title = E2ColoR('white') + movie_title + E2ColoR('white')

                # Description: Genre value in yellow, Rating value colored dynamically
                desc = ('Genre: ' + E2ColoR('yellow') + genre_str + E2ColoR('white') +
                        ' | Rating: ' + E2ColoR(rating_color_name) + rating + E2ColoR('white'))

                params = dict(cItem)
                params.update({
                    'title': colored_title,
                    'url': url,
                    'icon': icon,
                    'desc': desc,
                    'category': 'movie_torrents'
                })
                self.addDir(params)

            except Exception:
                printExc()

        # Next page
        try:
            next_page = self.cm.ph.getSearchGroups(data, r'href="([^"]+page=\d+[^"]*)"[^>]*>Next')[0]
        except Exception:
            next_page = ''
        if next_page:
            if not next_page.startswith('http'):
                next_page = self.MAIN_URL + next_page
            params = dict(cItem)
            params.update({'title': _('Next page'), 'url': next_page})
            self.addDir(params)

    ###################################################
    # LIST TORRENTS FOR MOVIE
    ###################################################
    def exploreItems(self, cItem):
        printDBG("TorrentYTSHost.exploreItems url[%s]" % cItem.get('url', ''))
        sts, data = self.cm.getPage(cItem.get('url', ''))
        if not sts or not data:
            return

        # Find section with torrent download links
        section = self.cm.ph.getDataBeetwenMarkers(
            data, '<em class="pull-left">Available in', '<br><span', False
        )[1]
        if not section:
            # fallback: try older structure
            section = self.cm.ph.getDataBeetwenMarkers(data, '<p class="hidden-xs hidden-sm">', '</p>', False)[1]

        blocks = self.cm.ph.getAllItemsBeetwenMarkers(section, '<a', '</a>')
        printDBG("blocks.searchMovies pattern[%s]" % blocks)

        for b in blocks:
            href = self.cm.ph.getSearchGroups(b, r'href="([^"]+)"')[0]
            if 'torrent/download/' not in href:
                continue

            quality = self.cm.ph.getDataBeetwenMarkers(b, '>', '<', False)[1].strip()
            if not quality:
                quality = self.cm.ph.getSearchGroups(b, r'Download [^"]+ (\d+p[^"]*) Torrent')[0]

            name = '%s [%s]' % (cItem.get('title', 'Torrent'), quality)

            params = dict(cItem)
            params.update({
                'title': name,
                'url': href,
                'icon': cItem.get('icon', ''),
                'desc': 'YTS Torrent %s' % quality,
                'category': 'video'
            })
            self.addVideo(params)

    ###################################################
    # SEARCH MOVIES
    ###################################################
    def searchMovies(self, pattern, cItem):
        if not pattern:
            pattern = self.searchPattern
        printDBG("TorrentYTSHost.searchMovies pattern[%s]" % pattern)
        safe_pattern = urllib_quote_plus(pattern)
        search_url = '%s/browse-movies/%s' % (self.MAIN_URL, safe_pattern)
        params = dict(cItem)
        params.update({'url': search_url, 'category': 'list_movies'})
        self.listMovies(params)

    def listSearchResult(self, cItem, searchPattern, searchType):
        printDBG("TorrentYTSHost.listSearchResult cItem[%s], searchPattern[%s] searchType[%s]" % (cItem, searchPattern, searchType))
        cItem = dict(cItem)
        cItem['url'] = self.SEARCH_URL + urllib_quote_plus(searchPattern)
        self.listMovies(cItem)
    
    ###################################################
    # PLAY TORRENT VIA TORSERVER - M3U GENERATION
    ###################################################
    def getLinksForVideo(self, cItem):
        self.updateTorServerUrl()
        
        # Check if TorServer is running
        ip = config.plugins.iptvplayer.torserver_ip.value.strip() or "127.0.0.1"
        port = int(config.plugins.iptvplayer.torserver_port.value.strip() or "8090")
        
        if not self.isPortOpen(ip, port, timeout=2.0):
            printDBG("TorServer not running, attempting to start...")
            if not self.ensureTorServerRunning():
                printDBG("TorServer could not be started.")
                return []

        torrent_url = cItem.get('url', '')
        if not torrent_url:
            printDBG("No torrent link found!")
            return []

        printDBG("Processing torrent URL: %s" % torrent_url)

        # URL encode the torrent URL
        encoded_url = urllib_quote_plus(torrent_url)
        
        # Generate M3U URL exactly as in your curl example
        m3u_url = "%s/stream?link=%s&m3u=m3u" % (self.TORSERVER_BASE, encoded_url)
        
        printDBG("M3U generation URL: %s" % m3u_url)
        
        # First, let's fetch the M3U content to verify it works
        try:
            sts, m3u_data = self.cm.getPage(m3u_url, {'header': {'accept': 'application/octet-stream'}})
            if sts and m3u_data:
                printDBG("M3U content received, length: %d" % len(m3u_data))
                printDBG("M3U content preview: %s" % m3u_data[:500])
                
                # Parse M3U to get actual stream URLs
                stream_urls = self.parseM3UContent(m3u_data, m3u_url)
                if stream_urls:
                    return stream_urls
                else:
                    printDBG("Failed to parse M3U content, returning M3U URL directly")
            else:
                printDBG("Failed to fetch M3U content")
        except Exception as e:
            printDBG("Error fetching M3U: %s" % str(e))
            printExc()

        # If M3U parsing fails, return the M3U URL directly
        url_with_meta = strwithmeta(m3u_url, {
            'iptv_proto': 'http',
            'Referer': self.TORSERVER_BASE,
            'User-Agent': 'Mozilla/5.0',
            'accept': 'application/octet-stream'
        })
        
        return [{'name': 'TorServer M3U', 'url': url_with_meta, 'need_resolve': 0}]

    def parseM3UContent(self, m3u_data, base_url):
        """Parse M3U content and extract stream URLs"""
        streams = []
        try:
            lines = m3u_data.split('\n')
            for line in lines:
                line = line.strip()
                # Look for actual stream URLs (not comments or metadata)
                if line and not line.startswith('#') and line.startswith('http'):
                    printDBG("Found stream URL in M3U: %s" % line)
                    
                    # Create URL with metadata
                    stream_url = strwithmeta(line, {
                        'iptv_proto': 'http',
                        'Referer': base_url,
                        'User-Agent': 'Mozilla/5.0 (X11; Linux armv7l) AppleWebKit/537.36'
                    })
                    
                    # Extract quality info from the line or use default
                    name = 'TorServer Stream'
                    if '720p' in line:
                        name = '720p Stream'
                    elif '1080p' in line:
                        name = '1080p Stream'
                    elif '480p' in line:
                        name = '480p Stream'
                        
                    streams.append({'name': name, 'url': stream_url, 'need_resolve': 0})
                    
            printDBG("Parsed %d streams from M3U" % len(streams))
        except Exception as e:
            printDBG("Error parsing M3U content: %s" % str(e))
            printExc()
            
        return streams

    def getVideoLinks(self, url):
        printDBG("TorrentYTSHost.getVideoLinks [%s]" % url)
        urlTab = []
        if self.cm.isValidUrl(url):
            return self.up.getVideoLinkExt(url)
        return urlTab

    def handleService(self, index, refresh=0, searchPattern='', searchType=''):
        printDBG('TorrentYTSHost.handleService start')

        CBaseHostClass.handleService(self, index, refresh, searchPattern, searchType)

        name = self.currItem.get("name", '')
        category = self.currItem.get("category", '')

        printDBG("handleService: >> name[%s], category[%s] " % (name, category))
        self.currList = []

        # MAIN MENU
        if name is None:
            self.listMainMenu({'name': 'category'})
        elif category == 'movie_torrents':
            self.exploreItems(self.currItem)
        elif category == 'explore_items':
            self.exploreItems(self.currItem)
        elif category == 'list_movies':
            self.listMovies(self.currItem)
        elif category == 'series_categories':
            self.listSeriesCategories(self.currItem)
        elif category == 'list_series':
            self.listUnits(self.currItem)
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

###################################################
# E2I WRAPPER
###################################################
class IPTVHost(CHostBase):

    def __init__(self):
        CHostBase.__init__(self, TorrentYTSHost(), True, [])