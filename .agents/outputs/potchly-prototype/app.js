const $ = selector => document.querySelector(selector);
const $$ = selector => [...document.querySelectorAll(selector)];

const categories = [
  ['✦','Hair & braiding','12 providers'], ['✿','Nails & beauty','8 providers'],
  ['⌂','Home cleaning','7 providers'], ['◌','Laundry & ironing','5 providers']
];
categories.forEach(([icon,name,count]) => {
  const button = document.createElement('button');
  button.className = 'category';
  button.innerHTML = `<i>${icon}</i><b>${name}</b><span>${count}</span>`;
  button.onclick = () => { go('request'); $('#service').value = name; };
  $('#categories').append(button);
});

const bids = [
  {name:'Nandi K.',role:'Protective style specialist',rating:'★ 4.9 (68) · 1.2 km',price:'R520',initials:'NK',perks:['Free wash & blow-dry','Hair included'],time:'Tomorrow at 10:00',featured:true},
  {name:'Zee Mobile Hair',role:'Mobile stylist',rating:'★ 4.8 (41) · Comes to you',price:'R480',initials:'ZM',perks:['At-home appointment'],time:'Tomorrow at 12:30'},
  {name:'Lerato T.',role:'Braids & natural hair',rating:'★ 4.7 (29) · 2.8 km',price:'R450',initials:'LT',perks:['Free touch-up within 5 days'],time:'Tomorrow at 09:00'}
];
$('#bidList').innerHTML = bids.map(x => `<article class="bid ${x.featured?'featured':''}">${x.featured?'<span class="tag">BEST MATCH</span>':''}<div class="pro"><i>${x.initials}</i><div><h3>${x.name} ✓</h3><p>${x.role}</p><small>${x.rating}</small></div><b>${x.price}</b></div><div class="perks">${x.perks.map(p=>`<span>✓ ${p}</span>`).join('')}</div><footer><span>${x.time}</span><button class="offer">View offer</button></footer></article>`).join('');

const screens = $$('.screen');
const nav = $('nav');
const navless = ['otp','account-ready','posted','paid','dispute-open','provider-verify','thanks'];
function go(id) {
  screens.forEach(screen => screen.classList.toggle('active', screen.id === id));
  nav.style.display = navless.includes(id) ? 'none' : 'flex';
  $$('nav button').forEach(button => button.classList.toggle('active', button.dataset.go === id));
  window.scrollTo({top:0, behavior:'smooth'});
}
$$('[data-go]').forEach(button => button.onclick = () => go(button.dataset.go));

function singleChoice(selector) {
  $$(selector).forEach(button => button.onclick = () => {
    $$(selector).forEach(item => item.classList.remove('selected'));
    button.classList.add('selected');
  });
}
singleChoice('.chips button');
singleChoice('.sort button');
singleChoice('.role-tabs button');
singleChoice('.payment-options button');

function showToast(text) {
  const toast = $('#toast');
  toast.textContent = text;
  toast.classList.add('show');
  setTimeout(() => toast.classList.remove('show'), 2300);
}

$('#authForm').onsubmit = event => {
  event.preventDefault();
  localStorage.setItem('potchly-user', JSON.stringify({name:$('#authName').value, verified:false}));
  go('otp');
};
$('#otpForm').onsubmit = event => {
  event.preventDefault();
  if ($('#otpInput').value !== '246810') { showToast('Use demo code 246810.'); return; }
  const user = JSON.parse(localStorage.getItem('potchly-user') || '{}');
  localStorage.setItem('potchly-user', JSON.stringify({...user, verified:true}));
  go('account-ready');
};

$('#requestForm').onsubmit = event => {
  event.preventDefault();
  const data = {service:$('#service').value, details:$('#details').value, date:$('#date').value, area:$('#area').value, budget:$('#budget').value};
  localStorage.setItem('potchly-request', JSON.stringify(data));
  $('#postedTitle').textContent = data.service;
  $('#postedMeta').textContent = `${data.area} · ${new Date(data.date+'T12:00').toLocaleDateString('en-ZA',{day:'numeric',month:'short'})}`;
  go('posted');
};

$$('.offer').forEach(button => button.onclick = () => go('checkout'));
$('#payDemo').onclick = () => { localStorage.setItem('potchly-payment','protected-demo'); go('paid'); };
$('#completeDemo').onclick = () => showToast('Completion confirmation sent to both parties.');

$('#disputeForm').onsubmit = event => {
  event.preventDefault();
  localStorage.setItem('potchly-dispute','DSP-208');
  go('dispute-open');
};
$('.upload-demo').onclick = () => showToast('Secure evidence upload would open here.');

$('#joinForm').onsubmit = event => {
  event.preventDefault();
  const name = $('#providerName').value;
  localStorage.setItem('potchly-provider', name);
  $('#founderName').textContent = name;
  go('provider-verify');
};
$('#verifyDemo').onclick = () => go('thanks');

$$('.toggle').forEach(button => button.onclick = () => {
  button.classList.toggle('on');
  button.textContent = button.classList.contains('on') ? 'On' : 'Off';
});
$$('.demo').forEach(button => {
  if (button.id === 'completeDemo') return;
  button.onclick = () => showToast('Demo action recorded in the audit log.');
});

$('#reset').onclick = () => {
  localStorage.clear();
  $('#requestForm').reset(); $('#joinForm').reset(); $('#authForm').reset();
  showToast('Prototype data reset.');
};
const tomorrow = new Date();
tomorrow.setDate(tomorrow.getDate()+1);
$('#date').value = tomorrow.toISOString().slice(0,10);
