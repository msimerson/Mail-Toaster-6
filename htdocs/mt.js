// Webmail clients: check URL is probed; href is the link destination.
const WEBMAIL = [
    { label: 'Roundcube',  href: '/roundcube/',  img: '/img/roundcube.png',  check: '/roundcube/'  },
    { label: 'Snappymail', href: '/snappymail/', img: '/img/snappymail.png', check: '/snappymail/' },
    { label: 'Qmailadmin', href: '/cgi-bin/qmailadmin/qmailadmin/', img: '/img/qmailadmin.png', check: '/cgi-bin/qmailadmin/qmailadmin/' },
];

// Admin tools: shown only when authenticated.
const ADMIN = [
    { label: 'rspamd',         href: '/rspamd/'           },
    { label: 'haraka',         href: '/haraka/'           },
    { label: 'watch',          href: '/watch',            },
    { label: 'snappy adm',     href: '/snappymail/?admin', check: '/snappymail/' },
    { label: 'dmarc',          href: '/dmarc'             },
    { label: 'munin',          href: '/munin/'            },
    { label: 'nagios',         href: '/nagios'            },
    { label: 'grafana',        href: '/grafana'           },
    { label: 'prometheus',     href: '/prometheus'        },
    { label: 'kibana',         href: '/kibana'            },
    { label: 'haproxy',        href: '/haproxy'           },
    { label: 'vqadmin',        href: '/cgi-bin/vqadmin/vqadmin.cgi' },
    // { label: 'rainloop adm',href: '/rainloop/?admin', check: '/rainloop/' },
];

// Returns true if the backend is reachable (any response except proxy errors).
async function isAlive(url) {
    try {
        const r = await fetch(url, {
            credentials: 'omit',
            signal: AbortSignal.timeout(2000),
        });
        // 502/503/504 = proxy couldn't reach the backend jail
        return ![404, 502, 503, 504].includes(r.status);
    } catch (_) {
        return false; // network error or timeout
    }
}

function addCard(service) {
    const a = document.createElement('a');
    a.className = 'card';
    a.href = service.href;
    a.innerHTML =
        `<img src="${service.img}" alt="${service.label}">` +
        `<div class="card-name">${service.label}</div>`;
    document.getElementById('webmail-grid').appendChild(a);
}

function addAdminLink(service) {
    const a = document.createElement('a');
    a.className = 'admin-link';
    a.href = service.href;
    a.textContent = service.label;
    document.getElementById('admin-grid').appendChild(a);
}

function probeAndAdd(services, addFn) {
    return services.map(async (svc) => {
        if (await isAlive(svc.check || svc.href)) addFn(svc);
    });
}

// Session cookie set by the /auth-login success page.
// No fetch — cookie check cannot trigger a browser auth dialog.
function isAuthed() {
    return document.cookie.split(';').some(c => c.trim() === 'is_admin=1');
}

document.getElementById('auth-btn').addEventListener('click', function () {
    window.location.href = '/auth-login';
});

// --- page load ---
// Webmail: probe unprotected URLs to find which clients are installed.
Promise.all(probeAndAdd(WEBMAIL, addCard));

// Admin: if authed, show every link (no probing — protected URLs would
// trigger browser auth dialogs via fetch).
if (isAuthed()) {
    document.getElementById('admin-section').hidden = false;
    document.getElementById('auth-section').hidden = true;
    ADMIN.forEach(svc => addAdminLink(svc));
}
