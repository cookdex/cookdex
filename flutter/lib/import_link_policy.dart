enum SocialSite {
  youtube('YouTube'),
  tiktok('TikTok'),
  instagram('Instagram'),
  threads('Threads'),
  facebook('Facebook'),
  x('X'),
  reddit('Reddit'),
  pinterest('Pinterest');

  const SocialSite(this.displayName);
  final String displayName;
}

const _socialDomains = {
  'youtube.com': SocialSite.youtube,
  'youtu.be': SocialSite.youtube,
  'tiktok.com': SocialSite.tiktok,
  'tiktokv.com': SocialSite.tiktok,
  'instagram.com': SocialSite.instagram,
  'instagr.am': SocialSite.instagram,
  'ig.me': SocialSite.instagram,
  'threads.net': SocialSite.threads,
  'threads.com': SocialSite.threads,
  'facebook.com': SocialSite.facebook,
  'fb.com': SocialSite.facebook,
  'fb.watch': SocialSite.facebook,
  'fb.me': SocialSite.facebook,
  'x.com': SocialSite.x,
  'twitter.com': SocialSite.x,
  't.co': SocialSite.x,
  'reddit.com': SocialSite.reddit,
  'redd.it': SocialSite.reddit,
  'reddit.app.link': SocialSite.reddit,
  'pin.it': SocialSite.pinterest,
  'pinimg.com': SocialSite.pinterest,
};

final _pinterestDomain = RegExp(
  r'(?:^|\.)pinterest\.(?:com|at|be|ca|ch|cl|co\.kr|co\.nz|co\.uk|com\.au|com\.br|com\.mx|de|dk|es|fr|ie|in|it|jp|kr|nl|nz|ph|pt|ru|se)$',
);

SocialSite? socialSite(Uri uri) {
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  for (final domain in _socialDomains.entries) {
    if (host == domain.key || host.endsWith('.${domain.key}')) {
      return domain.value;
    }
  }
  return _pinterestDomain.hasMatch(host) ? SocialSite.pinterest : null;
}

String blockedLinkMessage(SocialSite site) => site == SocialSite.pinterest
    ? "cookdex can't import from Pinterest. In Pinterest, tap Visit to open the recipe site, then share that page to cookdex."
    : "cookdex can't import from ${site.displayName}.";
