const state = { review: null, filters: { showPassed: false, severity: '', search: '' } };

const els = {
  repoPath: document.getElementById('repoPath'),
  metricTotal: document.getElementById('metricTotal'),
  metricReviewed: document.getElementById('metricReviewed'),
  metricPassed: document.getElementById('metricPassed'),
  metricFailed: document.getElementById('metricFailed'),
  metricGenerated: document.getElementById('metricGenerated'),
  reviewFile: document.getElementById('reviewFile'),
  btnRefresh: document.getElementById('btnRefresh'),
  btnOpenRepo: document.getElementById('btnOpenRepo'),
  tbody: document.querySelector('#tblReviews tbody'),
  fShowPassed: document.getElementById('fShowPassed'),
  fSeverity: document.getElementById('fSeverity'),
  fSearch: document.getElementById('fSearch'),
};

function esc(s){ return String(s??'').replace(/[&<>"']/g, c=> ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":"&#39;"}[c])); }
function fmtDate(s){ if(!s) return '-'; const d=new Date(s); return isNaN(d)?s:d.toLocaleString(); }

function render(){
  if(!state.review){ return; }
  els.repoPath.textContent = state.review.repoPath || '-';
  els.metricTotal.textContent = state.review.total ?? 0;
  els.metricReviewed.textContent = state.review.reviewed ?? 0;
  els.metricPassed.textContent = state.review.passed ?? 0;
  els.metricFailed.textContent = state.review.failed ?? 0;
  els.metricGenerated.textContent = fmtDate(state.review.generatedAt);
  const repoUrl = state.review.repoPath ? encodeURIComponent(state.review.repoPath) : '';
  els.btnOpenRepo.href = repoUrl ? `file:///${repoUrl}` : '#';

  const rows = (state.review.reviews || []).filter(r=>{
    if(!els.fShowPassed.checked && r.passed) return false;
    if(els.fSeverity.value && r.severity !== els.fSeverity.value) return false;
    const q = els.fSearch.value.toLowerCase();
    if(q && !(r.author?.toLowerCase().includes(q) || r.subject?.toLowerCase().includes(q) || r.shortHash?.includes(q))) return false;
    return true;
  });

  els.tbody.innerHTML = rows.map(r=>{
    const issuesHtml = (r.issues || []).map(i=>`<div class="issue ${i.type.toLowerCase()}"><strong>${esc(i.type)}:</strong> ${esc(i.message)}</div>`).join('');
    return `<tr class="${r.passed?'passed':'failed'} ${r.severity?.toLowerCase()}">
      <td><code>${esc(r.shortHash)}</code></td>
      <td>${esc(r.author)}</td>
      <td>${fmtDate(r.date)}</td>
      <td>${esc(r.subject)}</td>
      <td><span class="badge ${r.severity?.toLowerCase()}">${esc(r.severity)}</span></td>
      <td>${issuesHtml || '<em>none</em>'}</td>
    </tr>`;
  }).join('') || '<tr><td colspan="6" class="empty">No reviews match filters.</td></tr>';
}

els.reviewFile.addEventListener('change', e=>{
  const file = e.target.files[0]; if(!file) return;
  const reader = new FileReader();
  reader.onload = ()=>{ try{ state.review = JSON.parse(reader.result); render(); }catch(err){ alert('Invalid JSON: '+err.message); } };
  reader.readAsText(file);
});
els.btnRefresh.onclick = render;
els.fShowPassed.onchange = render;
els.fSeverity.onchange = render;
els.fSearch.oninput = render;
