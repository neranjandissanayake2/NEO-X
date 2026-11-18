import { initializeApp } from 'https://www.gstatic.com/firebasejs/13.4.0/firebase-app.js';
import { getAuth, createUserWithEmailAndPassword, signInWithEmailAndPassword, sendEmailVerification, sendPasswordResetEmail, signOut, onAuthStateChanged, updateProfile, reload } from 'https://www.gstatic.com/firebasejs/13.4.0/firebase-auth.js';
import { firebaseConfig } from './neo-firebase-config.js';
const $=id=>document.getElementById(id);
const message=$('message');
const say=t=>{message.textContent=t;};
const valid=Object.values(firebaseConfig).every(x=>typeof x==='string'&&!x.includes('PASTE_'));
if(!valid){say('Setup required: paste your exact Firebase Web App configuration into neo-firebase-config.js. See FIREBASE-SETUP-SINHALA.txt.');$('submitBtn').disabled=true;}
else {
 const auth=getAuth(initializeApp(firebaseConfig));
 const friendly=e=>({ 'auth/email-already-in-use':'This email is already registered.', 'auth/invalid-email':'Invalid email address.', 'auth/weak-password':'Use a stronger password (at least 8 characters).', 'auth/invalid-credential':'Incorrect email or password.', 'auth/too-many-requests':'Too many attempts. Please try later.', 'auth/network-request-failed':'Network error. Check internet connection.'}[e.code]||'Authentication error: '+(e.code||'Please try again.'));
 const lock=()=>window.neoMemberLock?.();
 const grant=user=>window.neoMemberView?.(user.displayName||user.email?.split('@')[0]||'Member');
 onAuthStateChanged(auth,async user=>{
  lock();
  if(!user)return;
  try{await reload(user);}catch(e){say(friendly(e));return;}
  if(!auth.currentUser?.emailVerified){say('Please verify your email before entering NEO-X. Check Inbox/Spam, then sign in again.');return;}
  grant(auth.currentUser);
 });
 $('authForm').addEventListener('submit',async e=>{
  e.preventDefault();e.stopImmediatePropagation();
  if(!$('auth').classList.contains('on')){say('Switch on the lamp first.');return;}
  const email=$('email').value.trim(),pass=$('password').value;
  $('submitBtn').disabled=true;say('Please wait…');
  try{
   if(window.mode==='up'||document.getElementById('signUpTab').classList.contains('active')){
    const name=$('fullName').value.trim();if(!name)throw Error('Enter your full name.');
    const cred=await createUserWithEmailAndPassword(auth,email,pass);
    await updateProfile(cred.user,{displayName:name});await sendEmailVerification(cred.user);
    await signOut(auth);lock();say('Account created! Verification email sent. Verify it, then sign in.');
   }else{
    const cred=await signInWithEmailAndPassword(auth,email,pass);
    await reload(cred.user);
    if(!cred.user.emailVerified){lock();say('Email not verified. Check your inbox and verify before accessing NEO-X.');}
    else {grant(cred.user);say('');}
   }
  }catch(err){say(friendly(err));}
  finally{$('submitBtn').disabled=false;$('password').value='';}
 },true);
 $('resetPassword').onclick=async()=>{const email=$('email').value.trim();if(!email){say('Enter your email address first.');return;}try{await sendPasswordResetEmail(auth,email);say('If the address is registered, a password reset email will arrive.');}catch(e){say(friendly(e));}};
 $('resendVerification').onclick=async()=>{const user=auth.currentUser;if(!user){say('Sign in with your unverified account first, then use Resend verification email.');return;}try{await reload(user);if(user.emailVerified){grant(user);return;}await sendEmailVerification(user);say('Verification email sent. Check Inbox/Spam.');}catch(e){say(friendly(e));}};
 $('logout').onclick=async()=>{try{await signOut(auth);lock();say('Signed out.');}catch(e){say(friendly(e));}};
}
