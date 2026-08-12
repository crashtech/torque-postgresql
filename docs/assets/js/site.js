---
# Front matter is here only so Liquid runs; the site-wide layout default must
# not reach an asset.
layout: null
sitemap: false
---
// Kramdown names the language in a class; the code frame renders it from a
// data attribute so the CSS needs one rule instead of one per language.
const LANGUAGE_LABELS = { bash: 'CLI', sql: 'SQL', erb: 'ERB', yaml: 'YAML', plaintext: 'Text' }

const labelBlock = (block) => {
  // A block that scrolls sideways has to be reachable by keyboard, or its
  // overflowing lines cannot be read without a mouse.
  const code = block.querySelector('pre')
  if (code) code.tabIndex = 0

  const language = [...block.classList].find((name) => name.startsWith('language-'))
  if (!language) return

  const name = language.replace('language-', '')
  block.dataset.lang = LANGUAGE_LABELS[name] || name
}

const flashCopied = (button, label) => {
  button.dataset.copied = 'true'
  if (label) button.textContent = 'Copied'

  const reset = () => {
    delete button.dataset.copied
    if (label) button.textContent = label
  }

  setTimeout(reset, 2000)
}

const copyBlock = (event) => {
  const button = event.currentTarget
  const code = button.parentElement.querySelector('pre')
  navigator.clipboard.writeText(code.innerText)
  flashCopied(button, 'Copy')
}

const addCopyButton = (block) => {
  const button = document.createElement('button')
  button.type = 'button'
  button.className = 'copy'
  button.textContent = 'Copy'
  button.addEventListener('click', copyBlock)
  block.appendChild(button)
}

const copyPill = (event) => {
  const button = event.currentTarget
  const code = button.parentElement.querySelector('code')
  navigator.clipboard.writeText(code.innerText.replace(/^\$\s*/, ''))
  flashCopied(button)
}

const setUpCode = () => {
  const blocks = document.querySelectorAll('div.highlighter-rouge')
  blocks.forEach(labelBlock)
  blocks.forEach(addCopyButton)
  document.querySelectorAll('[data-copy]').forEach((button) => button.addEventListener('click', copyPill))
}

const setUpVersionPicker = () => {
  const line = document.querySelector('[data-gem-line]')
  const picker = document.querySelector('[data-rails]')
  if (!line || !picker) return

  const rewrite = () => {
    line.innerHTML = `<span class="cmd">gem</span> <span class="str">'torque-postgresql'</span>, <span class="str">'${picker.value}'</span>`
  }

  picker.addEventListener('change', rewrite)
  rewrite()
}

// Search over page names only. The corpus is the navigation itself, so there is
// no index to build and nothing to download.
const PAGES = {{ site.data.nav | jsonify }}

const searchable = PAGES.flatMap((section) =>
  section.pages.map((item) => ({ ...item, section: section.title }))
)

const resultMarkup = (item) => {
  const label = `${item.title}<small>${item.section}</small>`
  return item.url
    ? `<li><a href="{{ site.baseurl }}${item.url}">${label}</a></li>`
    : `<li><span title="Not written yet">${label}</span></li>`
}

const setUpSearch = () => {
  const input = document.querySelector('[data-search]')
  const results = document.querySelector('[data-search-results]')
  if (!input || !results) return

  const render = () => {
    const query = input.value.trim().toLowerCase()
    if (!query) {
      results.innerHTML = ''
      return
    }

    const matches = searchable.filter((item) => item.title.toLowerCase().includes(query))
    results.innerHTML = matches.length
      ? matches.map(resultMarkup).join('')
      : '<li class="search-empty">No page by that name.</li>'
  }

  const dismiss = (event) => {
    if (!event.target.closest('.search')) results.innerHTML = ''
  }

  const clear = () => {
    input.value = ''
    results.innerHTML = ''
    input.blur()
  }

  // Typing into a list you cannot then step into is a dead end, so the arrow
  // keys walk the results and Enter follows the one in hand.
  const step = (offset) => {
    const links = [...results.querySelectorAll('a')]
    if (!links.length) return

    const current = links.indexOf(document.activeElement)
    const next = current < 0 ? (offset > 0 ? 0 : links.length - 1) : current + offset

    if (next < 0) input.focus()
    else links[Math.min(next, links.length - 1)].focus()
  }

  const onKey = (event) => {
    if (event.key === 'Escape') return clear()
    if (event.key === 'ArrowDown') { event.preventDefault(); step(1) }
    if (event.key === 'ArrowUp') { event.preventDefault(); step(-1) }
    if (event.key === 'Enter' && event.target === input) results.querySelector('a')?.click()
  }

  input.addEventListener('input', render)
  document.querySelector('.search').addEventListener('keydown', onKey)
  document.addEventListener('click', dismiss)
}

setUpCode()
setUpVersionPicker()
setUpSearch()
