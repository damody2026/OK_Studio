//! Nonblocking directory change notifications invalidate the in-memory catalogue.
//! Unsupported or unavailable watchers conservatively require a fresh signature.
use std::path::Path;

#[cfg(windows)]
mod platform {
 use super::*;
 use std::os::windows::ffi::OsStrExt;
 #[link(name="kernel32")]
 extern "system" {
  fn FindFirstChangeNotificationW(path:*const u16,subtree:i32,filter:u32)->isize;
  fn FindNextChangeNotification(handle:isize)->i32;
  fn FindCloseChangeNotification(handle:isize)->i32;
  fn WaitForSingleObject(handle:isize,timeout:u32)->u32;
 }
 use std::sync::{Arc,Mutex};
 use std::sync::atomic::{AtomicBool,AtomicU64,Ordering};
 const FILTER:u32=0x1|0x2|0x4|0x8|0x10|0x100; // FILE_NAME|DIR_NAME|ATTRIBUTES|SIZE|LAST_WRITE|SECURITY
 /// A tree is watched for the process's life by a `ReadDirectoryChangesW` that is always in flight (overlapped) on a
 /// thread that never ends. Both halves of that matter. The kernel sets `event` the moment it records a change -- as
 /// synchronously as `FindFirstChangeNotification` did, so an archive installed a moment before an open is still
 /// seen -- and hands over the *name* of what changed, which that one could not. And the thread never ends because
 /// Windows cancels a thread's pending I/O when it does, and a cancelled directory watch comes back *signalled*:
 /// the old watch was created on whichever worker opened the card, that worker finished, and the next open read the
 /// cancellation as "the tree changed" and walked the installation's ~8200 archives again, 215-280 ms, every open,
 /// with nothing in the tree touched. Docs/CARD_OPEN_PERF_20261117.md §十四.
 /// What the readers of a watched tree share: the event the kernel sets the moment it records a change (so a change
 /// is seen without waiting for any thread of ours to be scheduled), and the count of changes collected so far.
 struct Tree {event:isize,changes:AtomicU64,dead:AtomicBool}
 /// The watcher for a tree, started once per process. None when the tree cannot be watched (gone, no handle, no
 /// event, no thread): the caller then walks it every time, as before.
 fn tree_watcher(directory:&Path)->Option<Arc<Tree>> {
  static TREES:Mutex<Vec<(std::path::PathBuf,Arc<Tree>)>> = Mutex::new(Vec::new());
  let mut trees=TREES.lock().unwrap_or_else(|e|e.into_inner());
  if let Some((_,tree))=trees.iter().find(|(p,_)|p==directory) {
   return if tree.dead.load(Ordering::Relaxed){None}else{Some(tree.clone())};
  }
  let path:Vec<u16>=directory.as_os_str().encode_wide().chain(Some(0)).collect();
  // FILE_LIST_DIRECTORY, share everything (including DELETE, so watching never holds a tree hostage), OPEN_EXISTING,
  // FILE_FLAG_BACKUP_SEMANTICS (required for a directory) | FILE_FLAG_OVERLAPPED.
  let handle=unsafe{CreateFileW(path.as_ptr(),1,7,std::ptr::null_mut(),3,0x0200_0000|0x4000_0000,std::ptr::null_mut())};
  if handle == -1 {return None;}
  let event=unsafe{CreateEventW(std::ptr::null_mut(),1,0,std::ptr::null())}; // manual reset, unsignalled
  if event == 0 {unsafe{CloseHandle(handle);}return None;}
  let tree=Arc::new(Tree{event,changes:AtomicU64::new(0),dead:AtomicBool::new(false)});
  let (mine,named)=(tree.clone(),directory.to_owned());
  let armed=Arc::new(AtomicBool::new(false));
  let signal=armed.clone();
  if std::thread::Builder::new().name("ok-tree-watch".into())
   .spawn(move||watch_loop(handle,event,&named,&mine,&signal)).is_err() {
   unsafe{CloseHandle(handle);CloseHandle(event);}
   return None;
  }
  // The read must be in flight before the caller walks the tree and keeps the answer: a change recorded before it
  // is not reported at all.
  for _ in 0..1000 {
   if armed.load(Ordering::Relaxed){break;}
   std::thread::sleep(std::time::Duration::from_millis(1));
  }
  if !armed.load(Ordering::Relaxed)||tree.dead.load(Ordering::Relaxed){return None;}
  trees.push((directory.to_owned(),tree.clone()));
  Some(tree)
 }
 /// The one thread that owns a tree's watch, for the process's life. It has to be a thread that does not exit:
 /// Windows cancels a thread's pending I/O when it ends, and a cancelled directory watch comes back *signalled*.
 /// That is what the old watch did -- it was created on whichever worker opened the card, that worker finished, and
 /// the next open read the cancellation as "the tree changed" and walked the installation's ~8200 archives again,
 /// 215-250 ms per open, for the life of the reader. ERROR_OPERATION_ABORTED (995) on the first read of a tree is
 /// that bug, caught: Docs/CARD_OPEN_PERF_20261117.md §十三.
 fn watch_loop(handle:isize,event:isize,directory:&Path,tree:&Arc<Tree>,armed:&Arc<AtomicBool>){
  let mut buffer=vec![0u32;16*1024].into_boxed_slice(); // DWORD-aligned, as FILE_NOTIFY_INFORMATION requires
  let mut overlapped=Box::new([0u8;32]);
  loop {
   unsafe{ResetEvent(event);}
   *overlapped=[0u8;32]; // OVERLAPPED on x64: Internal, InternalHigh, Offset/Pointer, hEvent at 24
   overlapped[24..32].copy_from_slice(&(event as usize).to_ne_bytes());
   // `returned` must be null for an overlapped read (its value is meaningless until completion).
   if unsafe{ReadDirectoryChangesW(handle,buffer.as_mut_ptr().cast(),(buffer.len()*4) as u32,1,FILTER,
    std::ptr::null_mut(),overlapped.as_mut_ptr(),std::ptr::null_mut())} == 0 {
    let error=unsafe{GetLastError()};
    if std::env::var_os("OK_WATCH_TRACE").is_some() {
     crate::profile::line(format!("ok-extract: WATCH cannot watch {} (error {error})",directory.display()));
    }
    break;
   }
   armed.store(true,Ordering::Relaxed);
   if unsafe{WaitForSingleObject(event,0xFFFF_FFFF)} != 0 {break;}
   let mut transferred=0u32;
   if unsafe{GetOverlappedResult(handle,overlapped.as_mut_ptr(),&mut transferred,0)} == 0 {
    // The error first, before anything else on this thread (std::env::var_os clobbers it).
    let error=unsafe{GetLastError()};
    if std::env::var_os("OK_WATCH_TRACE").is_some() {
     crate::profile::line(format!("ok-extract: WATCH read failed on {} (error {error})",directory.display()));
    }
    // ERROR_NOTIFY_ENUM_DIR (1022): too many changes at once for the buffer. Something changed, the names are lost.
    // Anything else: the tree is gone or the watch broke, and it is walked every time from here on.
    if error != 1022 {break;}
    tree.changes.fetch_add(1,Ordering::Relaxed);
    continue;
   }
   if std::env::var_os("OK_WATCH_TRACE").is_some() {names(directory,&buffer,transferred);}
   // Count before re-arming (which resets the event), so a reader never falls between the two and sees neither.
   tree.changes.fetch_add(1,Ordering::Relaxed);
  }
  tree.dead.store(true,Ordering::Relaxed);
  tree.changes.fetch_add(1,Ordering::Relaxed);
  unsafe{CloseHandle(handle);CloseHandle(event);}
 }
 /// OK_WATCH_TRACE=1: what changed, by name. The one read-out that tells a false signal from a real change.
 fn names(directory:&Path,buffer:&[u32],transferred:u32){
  if transferred == 0 { // the buffer overflowed: this round's names are lost, which is itself worth saying
   crate::profile::line(format!("ok-extract: WATCH overflow under {}",directory.display()));
   return;
  }
  let bytes:&[u8]=unsafe{std::slice::from_raw_parts(buffer.as_ptr().cast(),transferred as usize)};
  let mut at=0usize;
  loop {
   if at + 12 > bytes.len() {break;}
   let read=|o:usize|u32::from_le_bytes([bytes[at+o],bytes[at+o+1],bytes[at+o+2],bytes[at+o+3]]) as usize;
   let (next,action,name_bytes)=(read(0),read(4),read(8));
   let name=if at+12+name_bytes<=bytes.len() {
    let units:Vec<u16>=bytes[at+12..at+12+name_bytes].chunks_exact(2).map(|c|u16::from_le_bytes([c[0],c[1]])).collect();
    String::from_utf16_lossy(&units)
   } else {String::from("<truncated>")};
   let what=match action {1=>"added",2=>"removed",3=>"modified",4=>"renamed-from",5=>"renamed-to",_=>"?"};
   crate::profile::line(format!("ok-extract: WATCH {what} {}\\{name}",directory.display()));
   if next == 0 {break;}
   at += next;
  }
 }
 pub(super) struct Watch {trees:Vec<(Arc<Tree>,u64)>,healthy:bool}
 impl Watch {
  pub(super) fn for_directories(directories:&[std::path::PathBuf])->Self {
   let mut watch=Self{trees:Vec::new(),healthy:true};
   for directory in directories {
    match tree_watcher(directory) {
     Some(tree)=>{
      // Let the watcher collect what it already has: a change recorded before this watch belongs to the walk the
      // caller is about to do, and the event stays signalled until the thread re-arms, so a snapshot taken while it
      // is still set would be read as a change by every later check.
      for _ in 0..50 {
       if unsafe{WaitForSingleObject(tree.event,0)} != 0 {break;}
       std::thread::sleep(std::time::Duration::from_millis(1));
      }
      let seen=tree.changes.load(Ordering::Relaxed);
      watch.trees.push((tree,seen));
     },
     None=>watch.healthy=false,
    }
   }watch
  }
  pub(super) fn changed(&mut self)->bool {
   if !self.healthy{return true;}
   // OK_WATCH_LEGACY=1: the control for the measurement -- always "changed", which is what the old watch reported in
   // practice (a walk per open). It buys the A/B of not walking without a second implementation to keep.
   if std::env::var_os("OK_WATCH_LEGACY").is_some(){return true;}
   let mut changed=false;
   for (tree,seen) in &mut self.trees {
    if tree.dead.load(Ordering::Relaxed){self.healthy=false;changed=true;continue;}
    // The event, not only the count: the kernel sets it the moment it records a change, so an archive installed a
    // moment ago is seen here even before the watcher thread has collected the name. A change can be answered twice
    // that way (once from the event, once from the count), which costs one walk and never a stale answer.
    if unsafe{WaitForSingleObject(tree.event,0)} == 0 {changed=true;}
    let now=tree.changes.load(Ordering::Relaxed);
    if now != *seen {*seen=now;changed=true;}
   }changed
  }
  pub(super) fn available(&self)->bool{self.healthy}
 }
 #[link(name="kernel32")]
 extern "system" {
  fn CreateFileW(path:*const u16,access:u32,share:u32,security:*mut u8,disposition:u32,flags:u32,template:*mut u8)->isize;
  fn ReadDirectoryChangesW(handle:isize,buffer:*mut u8,length:u32,subtree:i32,filter:u32,returned:*mut u32,
   overlapped:*mut u8,routine:*mut u8)->i32;
  fn CreateEventW(security:*mut u8,manual_reset:i32,initial:i32,name:*const u16)->isize;
  fn ResetEvent(event:isize)->i32;
  fn GetOverlappedResult(handle:isize,overlapped:*mut u8,transferred:*mut u32,wait:i32)->i32;
  fn CloseHandle(handle:isize)->i32;
  fn GetLastError()->u32;
 }
 /// OK_WATCH_TRACE=1: a `FindFirstChangeNotification` handle of our own on the tree, polled every 20 ms from a thread
 /// that never ends, beside the watcher that names every change. That pair is the evidence of §十三/§十四: the old
 /// watch's object was signalled on every card open while nothing under the tree changed, and this one -- made the
 /// same way, at the same moment, on the same tree, but on a thread that stays alive -- was never signalled once.
 /// Keep it: it is what tells a cancelled watch from a real change, should a watch start lying again.
 pub(super) fn trace(directory:&std::path::Path){
  if std::env::var_os("OK_WATCH_TRACE").is_none(){return;}
  static STARTED:std::sync::Mutex<Vec<std::path::PathBuf>> = std::sync::Mutex::new(Vec::new());
  {
   let mut started=STARTED.lock().unwrap_or_else(|e|e.into_inner());
   if started.iter().any(|p|p==directory){return;}
   started.push(directory.to_owned());
  }
  let polled=directory.to_owned();
  std::thread::Builder::new().name("ok-watch-poll".into()).spawn(move||poll_loop(&polled)).ok();
 }
 /// A notification handle of our own on the same tree, polled every 20 ms: it says *when* a watch becomes signalled,
 /// which the per-open check cannot (it only looks once per open). Pair it with the trace above: a signal with no
 /// change record named is a signal with no file behind it.
 fn poll_loop(directory:&std::path::Path){
  let path:Vec<u16>=directory.as_os_str().encode_wide().chain(Some(0)).collect();
  let handle=unsafe{FindFirstChangeNotificationW(path.as_ptr(),1,0x1|0x2|0x4|0x8|0x10|0x100)};
  crate::profile::line(format!("ok-extract: WATCH-POLL polling {} handle={handle:#x} (error {})",
   directory.display(),unsafe{GetLastError()}));
  if handle == -1 {return;}
  let mut rounds=0u32;
  loop {
   std::thread::sleep(std::time::Duration::from_millis(20));
   rounds+=1;
   let wait=unsafe{WaitForSingleObject(handle,0)};
   if rounds % 50 == 0 { // a heartbeat, so a silent poll is told apart from a poll that never fires
    crate::profile::line(format!("ok-extract: WATCH-POLL alive {rounds} wait={wait:#x}"));
   }
   if wait == 0 {
    crate::profile::line(format!("ok-extract: WATCH-POLL signalled {}",directory.display()));
    if unsafe{FindNextChangeNotification(handle)} == 0 {
     crate::profile::line(format!("ok-extract: WATCH-POLL stopped {}",directory.display()));
     unsafe{FindCloseChangeNotification(handle);}
     break;
    }
   }
  }
 }
}
#[cfg(not(windows))]
mod platform {
 use super::*;
 pub(super) struct Watch;
 impl Watch {
  pub(super) fn for_directories(_: &[std::path::PathBuf])->Self{Self}
  pub(super) fn changed(&mut self)->bool{true}
  pub(super) fn available(&self)->bool{false}
 }
 pub(super) fn trace(_:&std::path::Path){}
}
pub(crate) struct Watch(platform::Watch);
impl Watch {
 pub(crate) fn new(root:&Path)->Self{Self(platform::Watch::for_directories(&[root.join("abdata"),root.join("mods")]))}
 pub(crate) fn for_directory(directory:&Path)->Self{Self(platform::Watch::for_directories(&[directory.to_owned()]))}
 pub(crate) fn changed(&mut self)->bool{self.0.changed()}
 pub(crate) fn available(&self)->bool{self.0.available()}
 /// OK_WATCH_TRACE=1: read out every change under this tree, by name (see `platform::trace`).
 pub(crate) fn trace(directory:&Path){platform::trace(directory);}
}
#[cfg(all(test,windows))]
#[test]
fn recursive_watch_detects_asset_changes_without_timed_cache_expiry(){
 let id=std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
 let root=std::env::temp_dir().join(format!("ok-catalog-watch-{id}"));
 std::fs::create_dir_all(root.join("abdata/list")).unwrap();std::fs::create_dir_all(root.join("mods")).unwrap();
 let mut watch=Watch::new(&root);assert!(watch.available());assert!(!watch.changed());
 std::fs::write(root.join("abdata/list/test.unity3d"),[1,2,3]).unwrap();
 let start=std::time::Instant::now();while !watch.changed(){assert!(start.elapsed()<std::time::Duration::from_secs(1));std::thread::sleep(std::time::Duration::from_millis(1));}
 std::fs::write(root.join("mods/test.zipmod"),[4,5,6]).unwrap();
 let start=std::time::Instant::now();while !watch.changed(){assert!(start.elapsed()<std::time::Duration::from_secs(1));std::thread::sleep(std::time::Duration::from_millis(1));}
 let mut unavailable=Watch::new(&root.join("missing"));assert!(!unavailable.available());assert!(unavailable.changed());
}
