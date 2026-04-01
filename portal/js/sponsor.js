// SchoolAir Sponsor Page Logic
const SUPABASE_URL = 'https://gzbuvywxrzcovqohmbol.supabase.co'

document.addEventListener('DOMContentLoaded', async () => {
    await loadSponsorsWall()
    handleUrlParams()
})

async function loadSponsorsWall() {
    try {
        const resp = await fetch(`${SUPABASE_URL}/functions/v1/get-schoolair-sponsors`)
        if (!resp.ok) throw new Error('API not available')
        const data = await resp.json()

        // Update progress bar
        if (data.progress) {
            const pct = (data.progress.protected / data.progress.total) * 100
            document.getElementById('progressBar').style.width = pct + '%'
            document.getElementById('progressCount').textContent = data.progress.protected
            document.getElementById('progressTotal').textContent = data.progress.total
        }

        // Render sponsor tiles
        const grid = document.getElementById('sponsorsGrid')
        const named = (data.sponsors || []).filter(s => s.display_name)
        if (named.length === 0) {
            grid.innerHTML = '<p class="empty-wall">Be the first to sponsor a classroom!</p>'
            return
        }
        grid.innerHTML = named.map(s => `<div class="sponsor-tile">
            <strong>${escapeHtml(s.display_name)}</strong>
            ${s.dedication ? `<span class="tile-dedication">${escapeHtml(s.dedication)}</span>` : ''}
            <small class="tile-type">${formatType(s)}</small>
        </div>`).join('')
    } catch (err) {
        // API not deployed yet — show fallback
        console.log('Sponsors API not available yet:', err.message)
    }
}

function formatType(s) {
    if (s.sponsor_type === 'patron') return `Monthly Patron \u00b7 \u20ac${s.tier}/mo`
    return s.kit_type === 'installed' ? 'Installed Kit Sponsor' : 'Home Build Kit Sponsor'
}

function startCheckout(type, kitType, tier) {
    const modal = document.getElementById('checkoutModal')
    modal.style.display = 'flex'
    modal.dataset.type = type
    modal.dataset.kitType = kitType || ''
    modal.dataset.tier = tier || ''

    // Update modal title
    const title = document.getElementById('checkoutTitle')
    if (type === 'sponsor') {
        title.textContent = kitType === 'exterior'
            ? 'Sponsor an Exterior Unit — \u20ac125'
            : 'Sponsor an Interior Unit — \u20ac105'
    } else {
        title.textContent = `Become a Monthly Patron — \u20ac${tier}/mo`
    }

    // Reset form
    document.getElementById('checkoutEmail').value = ''
    document.getElementById('checkoutDisplayName').value = ''
    document.getElementById('checkoutClassroom').value = ''
    document.getElementById('checkoutQuantity').value = '1'
    const btn = document.getElementById('checkoutSubmitBtn')
    btn.disabled = false
    btn.textContent = 'Proceed to Payment'
}

function closeCheckoutModal() {
    document.getElementById('checkoutModal').style.display = 'none'
}

async function submitCheckout() {
    const modal = document.getElementById('checkoutModal')
    const email = document.getElementById('checkoutEmail').value.trim()
    const displayName = document.getElementById('checkoutDisplayName').value.trim()
    const classroom = document.getElementById('checkoutClassroom').value.trim()
    const quantity = parseInt(document.getElementById('checkoutQuantity').value) || 1

    if (!email) {
        alert('Email is required')
        return
    }

    const btn = document.getElementById('checkoutSubmitBtn')
    btn.disabled = true
    btn.textContent = 'Redirecting to payment...'

    try {
        const resp = await fetch(`${SUPABASE_URL}/functions/v1/create-schoolair-checkout`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                type: modal.dataset.type,
                kit_type: modal.dataset.kitType || undefined,
                tier: modal.dataset.tier ? parseInt(modal.dataset.tier) : undefined,
                email,
                quantity,
                display_name: displayName || undefined,
                classroom: classroom || undefined,
                success_url: window.location.origin + window.location.pathname + '?success=true',
                cancel_url: window.location.origin + window.location.pathname + '?cancelled=true',
            })
        })
        const data = await resp.json()
        if (data.url) {
            window.location.href = data.url
        } else {
            throw new Error(data.error || 'Failed to create checkout')
        }
    } catch (err) {
        alert('Error: ' + err.message)
        btn.disabled = false
        btn.textContent = 'Proceed to Payment'
    }
}

function handleUrlParams() {
    const params = new URLSearchParams(window.location.search)
    if (params.get('success')) {
        showBanner('success', 'Thank you for your sponsorship! Check your email for confirmation and a link to customize your display name.')
        window.history.replaceState({}, '', window.location.pathname)
    }
    if (params.get('cancelled')) {
        showBanner('cancel', 'Checkout was cancelled. No worries \u2014 you can try again anytime.')
        window.history.replaceState({}, '', window.location.pathname)
    }
    if (params.get('edit')) {
        showLabelEditor(params.get('edit'))
    }
}

function showLabelEditor(token) {
    document.querySelector('.sponsor-main-content').style.display = 'none'
    const editor = document.getElementById('labelEdit')
    editor.style.display = 'block'

    document.getElementById('labelForm').onsubmit = async (e) => {
        e.preventDefault()
        const btn = e.target.querySelector('button[type="submit"]')
        btn.disabled = true
        btn.textContent = 'Saving...'

        try {
            const resp = await fetch(`${SUPABASE_URL}/functions/v1/update-schoolair-label`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    token,
                    display_name: document.getElementById('editDisplayName').value.trim(),
                    dedication: document.getElementById('editDedication').value.trim() || undefined,
                })
            })
            if (resp.ok) {
                showBanner('success', 'Your display name has been updated!')
                setTimeout(() => window.location.href = 'sponsor.html', 2000)
            } else {
                alert('Failed to update. The link may have expired.')
                btn.disabled = false
                btn.textContent = 'Save Changes'
            }
        } catch (err) {
            alert('Error: ' + err.message)
            btn.disabled = false
            btn.textContent = 'Save Changes'
        }
    }
}

function showBanner(type, message) {
    const banner = document.createElement('div')
    banner.className = `banner banner-${type}`
    banner.innerHTML = `<p>${message}</p><button onclick="this.parentElement.remove()">\u00d7</button>`
    document.body.prepend(banner)
}

function escapeHtml(str) {
    const div = document.createElement('div')
    div.textContent = str
    return div.innerHTML
}
