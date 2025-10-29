# -*- coding: utf-8 -*-
###################################################
#  TorrentYTS Host for E2iPlayer (EZTV + TorrServer)
#  Compatible with Python 2.7 / 3.x
#  Last modified: 29/10/2025 - popking (odem2014)
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
    return 'https://eztv.tf/'  # main url of host

###################################################
# MAIN HOST CLASS
###################################################
class TorrentEZTVHost(CBaseHostClass):

    def __init__(self):
        CBaseHostClass.__init__(self, {'history': 'eztv.torrent', 'cookie': 'eztv.cookie'})
        self.MAIN_URL = 'https://eztv.tf'
        self.SEARCH_URL = self.MAIN_URL + '/search/'
        # --- TorrServer Configuration ---
        self.TORSERVER_PORT = 8090
        self.TORSERVER_IP = "127.0.0.1"
        self.TORSERVER_PATH = "/media/hdd/TorrServer"
        self.TORSERVER_CONFIG = "/media/hdd/config"
        self.DEFAULT_ICON_URL = 'https://raw.githubusercontent.com/popking159/mye2iplayer/refs/heads/main/torrenteztv.jpg'
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
        printDBG('TorrentEZTVHost.listMainMenu')
        MAIN_CAT_TAB = [
            {'category': 'list_movies', 'title': _('Series'), 'url': self.getFullUrl('/home')},
        ] + self.searchItems()
        self.listsTab(MAIN_CAT_TAB, cItem)

    ###################################################
    # LIST MOVIES
    ###################################################
    def listMovies(self, cItem):
        printDBG("TorrentEZTVHost.listMovies url[%s]" % cItem.get('url', ''))
        sts, data = self.cm.getPage(cItem.get('url', ''))
        if not sts or not data:
            return

        try:
            main_block_series = self.cm.ph.getAllItemsBeetwenMarkers(
                data, '<tr class="forum_space_border">', '</table>', False
            )[0]
        except Exception:
            main_block_series = data

        items = self.cm.ph.getAllItemsBeetwenMarkers(main_block_series, '<tr name="hover"', '</tr>', False)
        printDBG("Found %d serie items" % len(items))

        for item in items:
            try:
                # --- Extract episode URLs (/ep/...)
                url = self.cm.ph.getSearchGroups(item, r'href="(/ep/[^"]+)"')[0]
                if not url:
                    continue
                full_url = self.MAIN_URL + url

                # --- Extract title
                title = self.cm.ph.getSearchGroups(item, r'class="epinfo"[^>]*>([^<]+)<')[0].strip()
                if not title:
                    title = self.cm.ph.getSearchGroups(item, r'title="([^"]+)"')[0].strip()

                if not title:
                    continue

                # --- Extract size and age
                size = self.cm.ph.getSearchGroups(item, r'<td[^>]*>([\d\.]+\s*[MGK]B)</td>')[0].strip() or 'Unknown'
                age = self.cm.ph.getSearchGroups(item, r'<td[^>]*>(\d+\s*[smhdwy])</td>')[0].strip() or 'Unknown'

                # --- COLORIZATION ---
                def safe_sub(pattern, color, text, flags=0):
                    try:
                        return re.sub(pattern,
                                      lambda m: E2ColoR(color) + m.group(0) + E2ColoR('white'),
                                      text, flags=flags)
                    except:
                        return text

                color_title = title

                # 1️⃣ Colorize show tag [eztv]
                color_title = safe_sub(r'\[eztv\]', 'khaki', color_title, re.I)

                # 2️⃣ Resolution (480p, 720p, 1080p, 2160p)
                color_title = safe_sub(r'\b(480p|720p|1080p|2160p)\b', 'fuchsia', color_title, re.I)

                # 3️⃣ Codec formats (x264, x265, h264, hevc, xvid)
                color_title = safe_sub(r'\b(x264|x265|h\.?264|h\.?265|hevc|xvid)\b', 'olive', color_title, re.I)

                # 4️⃣ Source tags (WEB, WEBRip, WEB-DL, HDTV, BluRay)
                color_title = safe_sub(r'\b(WEB[- ]?DL|WEB[- ]?Rip|WEB|HDTV|BluRay|DVDRip|CAM|TS)\b', 'aqua', color_title, re.I)

                # 5️⃣ Release group (after a dash, e.g. -FENiX)
                color_title = safe_sub(r'-(\w+)$', 'violet', color_title, re.I)

                # 6️⃣ Season/Episode combined (S01E05)
                color_title = safe_sub(r'\bS\d{1,2}E\d{1,2}\b', 'yellow', color_title, re.I)

                # 7️⃣ Individual season or episode (S01, E05)
                color_title = safe_sub(r'\bS\d{1,2}\b', 'green', color_title, re.I)
                color_title = safe_sub(r'\bE\d{1,2}\b', 'yellow', color_title, re.I)

                # 8️⃣ Year patterns
                color_title = safe_sub(r'\b(19\d{2}|20\d{2})\b', 'orange', color_title)

                # --- Description
                desc = (
                    "Size: " + E2ColoR('yellow') + size + E2ColoR('white') +
                    " | Age: " + E2ColoR('cyan') + age + E2ColoR('white')
                )

                # --- Add directory entry
                params = dict(cItem)
                params.update({
                    'title': color_title,
                    'url': full_url,
                    'desc': desc,
                    'icon': '',
                    'category': 'movie_torrents'
                })
                self.addDir(params)

            except Exception as e:
                printDBG("Error parsing item: %s" % str(e))

        # --- NEXT PAGE ---
        next_page = self.cm.ph.getSearchGroups(
            data, r'<a href="([^"]+)" title="EZTV Torrents - Page: \d+"> next page</a>'
        )[0]
        if next_page:
            if not next_page.startswith('http'):
                next_page = self.MAIN_URL + next_page
            params = dict(cItem)
            params.update({'title': _('Next Page ➜'), 'url': next_page})
            self.addDir(params)
    
    ###################################################
    # LIST TORRENTS FOR MOVIE
    ###################################################
    def exploreItems(self, cItem):
        printDBG("TorrentEZTVHost.exploreItems url[%s]" % cItem.get('url', ''))
        base_url = 'https://eztv.tf'

        sts, data = self.cm.getPage(cItem.get('url', ''))
        if not sts or not data:
            return

        # --- Extract main page sections ---
        main_section = self.cm.ph.getDataBeetwenMarkers(
            data, 'class="episode_left_column">', 'class="section_post_header">Alternate Releases', False
        )[1]
        if not main_section:
            main_section = data

        # 1️⃣ Section 1 - Episode Info (poster, title, season/episode)
        section1 = self.cm.ph.getDataBeetwenMarkers(
            main_section, '<td class="section_post_header">Episode Breakdown</td>', '</table>', False
        )[1]

        # 2️⃣ Section 2 - Download Links (torrent, magnet)
        section2 = self.cm.ph.getDataBeetwenMarkers(
            main_section, '<td class="section_post_header">Download Links</td>', '</table>', False
        )[1]

        # 3️⃣ Section 3 - Torrent Info (hash, size, release date, resolution)
        section3 = self.cm.ph.getDataBeetwenMarkers(
            main_section, '<td class="section_post_header">Torrent Info</td>', '</table>', False
        )[1]

        # -------------------------------
        # 🔹 Extract details from section 1
        # -------------------------------
        show_title = self.cm.ph.getSearchGroups(section1, r'title="([^"]+)"')[0]
        poster = self.cm.ph.getSearchGroups(section1, r'src="([^"]+)"')[0]
        if poster and not poster.startswith('http'):
            poster = base_url + poster

        season = self.cm.ph.getSearchGroups(section1, r'<b>Season:</b>\s*(\d+)')[0]
        episode = self.cm.ph.getSearchGroups(section1, r'<b>Episode:</b>\s*(\d+)')[0]

        # -------------------------------
        # 🔹 Extract details from section 2
        # -------------------------------
        torrent_link = self.cm.ph.getSearchGroups(section2, r'href="(https?://[^"]+\.torrent)"')[0]
        magnet_link = self.cm.ph.getSearchGroups(section2, r'href="(magnet:[^"]+)"')[0]

        added_text = self.cm.ph.getSearchGroups(section2, r'Added\s*([^<]+)<')[0]
        uploader = self.cm.ph.getSearchGroups(section2, r'by\s*<span[^>]*>([^<]+)<')[0]

        # -------------------------------
        # 🔹 Extract details from section 3
        # -------------------------------
        torrent_file = self.cm.ph.getSearchGroups(section3, r'<b>Torrent File:</b>\s*([^<]+)<')[0]
        torrent_hash = self.cm.ph.getSearchGroups(section3, r'<b>Torrent Hash:</b>\s*([^<]+)<')[0]
        file_size = self.cm.ph.getSearchGroups(section3, r'<b>Filesize:</b>\s*([^<]+)<')[0]
        released = self.cm.ph.getSearchGroups(section3, r'<b>Released:</b>\s*([^<]+)<')[0]
        resolution = self.cm.ph.getSearchGroups(section3, r'<b>Resolution:</b>\s*([^<]+)<')[0]
        format_ = self.cm.ph.getSearchGroups(section3, r'<b>File Format:</b>\s*([^<]+)<')[0]

        # -------------------------------
        # 🔹 Build detailed description
        # -------------------------------
        try:
            white = E2ColoR('white')
            col_hash = E2ColoR('yellow')
            col_size = E2ColoR('cyan')
            col_released = E2ColoR('crimson')
            col_res = E2ColoR('orange')
            col_fmt = E2ColoR('violet')
            col_added = E2ColoR('dodgerblue')
            col_upl = E2ColoR('gold')
        except Exception:
            # fallback: empty strings (no colors)
            white = col_hash = col_size = col_released = col_res = col_fmt = col_added = col_upl = ''

        desc_lines = []
        if torrent_hash:
            desc_lines.append(col_hash + "Hash: " + white + torrent_hash + white)
        if file_size:
            desc_lines.append(col_size + "Size: " + white + file_size + white)
        if released:
            desc_lines.append(col_released + "Released: " + white + released + white)
        if resolution:
            desc_lines.append(col_res + "Resolution: " + white + resolution + white)
        if format_:
            desc_lines.append(col_fmt + "Format: " + white + format_ + white)
        if added_text:
            desc_lines.append(col_added + "Added: " + white + added_text + white)
        if uploader:
            desc_lines.append(col_upl + "Uploader: " + white + uploader + white)

        full_desc = "\n".join(desc_lines).strip()

        # -------------------------------
        # Add the Torrent item (if present)
        # -------------------------------
        if torrent_link:
            params = dict(cItem)
            params.update({
                'title': E2ColoR('cyan') + '⬇ Download Torrent' + E2ColoR('white'),
                'url': torrent_link,
                'icon': poster or cItem.get('icon', ''),
                'desc': full_desc,
                'category': 'video'
            })
            self.addVideo(params)

        # -------------------------------
        # Add the Magnet item (if present)
        # -------------------------------
        if magnet_link:
            params = dict(cItem)
            params.update({
                'title': E2ColoR('orange') + '🧲 Magnet Link' + E2ColoR('white'),
                'url': magnet_link,
                'icon': poster or cItem.get('icon', ''),
                'desc': full_desc,
                'category': 'video'
            })
            self.addVideo(params)

    ###################################################
    # SEARCH MOVIES
    ###################################################
    def searchMovies(self, pattern, cItem):
        if not pattern:
            pattern = self.searchPattern
        printDBG("TorrentEZTVHost.searchMovies pattern[%s]" % pattern)
        safe_pattern = urllib_quote_plus(pattern)
        search_url = '%s/browse-movies/%s' % (self.MAIN_URL, safe_pattern)
        params = dict(cItem)
        params.update({'url': search_url, 'category': 'list_movies'})
        self.listMovies(params)

    def listSearchResult(self, cItem, searchPattern, searchType):
        printDBG("TorrentEZTVHost.listSearchResult cItem[%s], searchPattern[%s] searchType[%s]" % (cItem, searchPattern, searchType))
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
        printDBG("TorrentEZTVHost.getVideoLinks [%s]" % url)
        urlTab = []
        if self.cm.isValidUrl(url):
            return self.up.getVideoLinkExt(url)
        return urlTab

    def handleService(self, index, refresh=0, searchPattern='', searchType=''):
        printDBG('TorrentEZTVHost.handleService start')

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
        CHostBase.__init__(self, TorrentEZTVHost(), True, [])