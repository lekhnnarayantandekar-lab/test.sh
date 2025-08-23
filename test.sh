#!/usr/bin/env bash
set -euo pipefail

ROOT="ecomx"

write() {
  local path="$1"
  shift
  mkdir -p "$(dirname "$ROOT/$path")"
  cat > "$ROOT/$path" <<'EOF'
'"$*"'EOF
}

write_raw() {
  local path="$1"
  shift
  mkdir -p "$(dirname "$ROOT/$path")"
  cat > "$ROOT/$path" <<'EOF'
'"$*"'EOF
}

mkdir -p "$ROOT"

# .htaccess
write_raw ".htaccess" '<?php /* placeholder for PHP servers */ ?>'
cat > "$ROOT/.htaccess" <<'HTA'
RewriteEngine On
Options -Indexes

# Force HTTPS (uncomment if SSL ready)
#RewriteCond %{HTTPS} !=on
#RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]

# Security headers (can also set in Apache conf)
<IfModule mod_headers.c>
 Header set X-Frame-Options "SAMEORIGIN"
 Header set X-Content-Type-Options "nosniff"
 Header set Referrer-Policy "no-referrer-when-downgrade"
 Header set X-XSS-Protection "1; mode=block"
</IfModule>

# Block direct access to internal dirs
RewriteRule ^(db|includes)/ - [F,L]

# Route API
RewriteRule ^api/(.*)$ api/$1 [L,NC,QSA]

# Pretty store URLs: /store/<slug>
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^store/([a-zA-Z0-9_-]+)/?$ store/index.php?store=$1 [QSA,L]
HTA

# config.php
write_raw "config.php" '<?php
return [
  "env" => "production",
  "base_url" => "http://localhost/ecomx",
  "db" => [
    "host" => "localhost",
    "name" => "ecomx",
    "user" => "root",
    "pass" => "",
    "charset" => "utf8mb4"
  ],
  "security" => [
    "password_algo" => PASSWORD_ARGON2ID,
    "session_name" => "ecomx_sid",
    "csrf_token_name" => "ecomx_csrf",
    "jwt_secret" => "CHANGE_THIS_RANDOM_64_CHARS",
    "allow_2fa" => true,
  ],
  "stores" => [
    "default_theme" => "default",
    "allow_whitelabel" => true,
    "powered_by" => false
  ],
  "payments" => [
    "default_driver" => "offline",
    "drivers" => [
      "offline" => ["enabled"=>true],
      "cod" => ["enabled"=>true],
      "bank_transfer" => ["enabled"=>true],
      "razorpay" => ["enabled"=>false, "mode"=>"offline"],
      "paytm" => ["enabled"=>false, "mode"=>"offline"],
      "ccavenue" => ["enabled"=>false, "mode"=>"offline"],
      "instamojo" => ["enabled"=>false, "mode"=>"offline"],
      "stripe" => ["enabled"=>false, "mode"=>"offline"],
      "paypal" => ["enabled"=>false, "mode"=>"offline"]
    ]
  ],
  "analytics" => [
    "enabled" => true,
    "respect_dnt" => true,
    "retention_days" => 365,
    "ip_anonymize" => true
  ],
  "i18n" => [
    "default_locale" => "en_IN",
    "supported" => ["en_IN","hi_IN"]
  ],
  "currency" => [
    "default" => "INR",
    "supported" => ["INR","USD","EUR"],
    "rounding" => 2
  ],
];
'

# README.txt
write_raw "README.txt" 'EcomX — Self-Hosted Ecommerce & Content Platform (PHP 8 / MySQL 8)
/install steps:
1) Create DB (MySQL 8) and user. Import schema.sql then demo.sql.
2) Edit config.php with DB credentials and base_url.
3) Upload to cPanel -> public_html/ecomx (or subfolder) and Extract ZIP.
4) Visit /ecomx/install.php to initialize admin password (admin@example.com / Admin@123).
Modules: Users, Stores, Products, Cart, Orders, Returns, Invoices, Shipping, Payments (offline/COD/bank + stubs),
Affiliate, Ads, Vendor, POS, B2B, Support, Notifications, Analytics, AI (local), Multi-language & currency.
Security: Argon2id, CSRF, role-based guards, 2FA (TOTP), audit logs. Use HTTPS.
'

# install.php
write_raw "install.php" '<?php
require __DIR__."/includes/db.php";
try { $pdo = db(); } catch (Throwable $e) { die("DB error: ".$e->getMessage()); }
$admin = $pdo->query("SELECT * FROM users WHERE email='admin@example.com'")->fetch();
if ($admin) {
  if (strpos($admin["password_hash"], "argon2id")===false) {
    $hash = password_hash("Admin@123", PASSWORD_ARGON2ID);
    $st = $pdo->prepare("UPDATE users SET password_hash=? WHERE id=?");
    $st->execute([$hash,$admin["id"]]);
    echo "Admin password reset. Email: admin@example.com / Admin@123<br>";
  } else {
    echo "Admin exists. You can login.<br>";
  }
} else {
  echo "Import schema.sql and demo.sql first.<br>";
}
echo "OK: DB Connected. Ensure /assets/img/uploads is writable.";
'

# root sql
mkdir -p "$ROOT"
cp /dev/null "$ROOT/schema.sql" || true
cp /dev/null "$ROOT/demo.sql" || true

# db tools
write_raw "db/migrate.php" '<?php require __DIR__."/../includes/db.php"; echo "Run SQL migrations via schema.sql\n";'
write_raw "db/seed.php"    '<?php require __DIR__."/../includes/db.php"; echo "Seed via demo.sql\n";'

# includes core
write_raw "includes/db.php" '<?php
$config = require __DIR__."/../config.php";
$GLOBALS["config"] = $config;
function db(): PDO {
  static $pdo;
  if ($pdo) return $pdo;
  $cfg = $GLOBALS["config"]["db"];
  $dsn = "mysql:host={$cfg["host"]};dbname={$cfg["name"]};charset={$cfg["charset"]}";
  $pdo = new PDO($dsn, $cfg["user"], $cfg["pass"], [
    PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC,
  ]);
  return $pdo;
}
'

write_raw "includes/util.php" '<?php
function json_response($arr, int $code=200){ http_response_code($code); header("Content-Type: application/json"); echo json_encode($arr); exit; }
function redirect($url){ header("Location: ".$url); exit; }
function now(){ return date("Y-m-d H:i:s"); }
function env($k,$d=null){ return $GLOBALS["config"][$k] ?? $d; }
'

write_raw "includes/csrf.php" '<?php
function csrf_init(){ if (empty($_SESSION["csrf"])) $_SESSION["csrf"] = bin2hex(random_bytes(32)); }
function csrf_token(){ return $_SESSION["csrf"] ?? ""; }
function csrf_field(){ $t = htmlspecialchars(csrf_token()); echo "<input type=\"hidden\" name=\"csrf\" value=\"$t\">"; }
function csrf_check(){
  if (($_SERVER["REQUEST_METHOD"] ?? "GET") === "GET") return;
  $in = $_POST["csrf"] ?? ($_SERVER["HTTP_X_CSRF_TOKEN"] ?? "");
  if (!$in || !hash_equals($_SESSION["csrf"] ?? "", $in)) { http_response_code(419); exit("CSRF failed"); }
}
'

write_raw "includes/guard.php" '<?php
function require_login(){ if (!isset($_SESSION["uid"])) { http_response_code(401); exit("Unauthorized"); } }
function require_role(array $roles){ if (!isset($_SESSION["uid"]) || !in_array($_SESSION["role"]??"", $roles,true)) { http_response_code(403); exit("Forbidden"); } }
'

write_raw "includes/validation.php" '<?php
function is_email($v){ return filter_var($v, FILTER_VALIDATE_EMAIL); }
function not_empty($v){ return isset($v) && trim((string)$v) !== ""; }
'

write_raw "includes/audit.php" '<?php
function audit_log($user_id, $action, $detail=""){
  $st = db()->prepare("INSERT INTO audit_log (user_id, action, detail) VALUES (?,?,?)");
  $st->execute([$user_id,$action,$detail]);
}
'

write_raw "includes/i18n.php" '<?php
function i18n_init(){ if (empty($_SESSION["locale"])) $_SESSION["locale"] = $GLOBALS["config"]["i18n"]["default_locale"]; }
function set_locale($l){ if (in_array($l, $GLOBALS["config"]["i18n"]["supported"], true)) $_SESSION["locale"]=$l; }
function t($s){ return $s; } // placeholder
'

write_raw "includes/currency.php" '<?php
function currency_default(){ return $GLOBALS["config"]["currency"]["default"]; }
function format_currency($amount, $cur=null){ $cur=$cur?:currency_default(); return $cur." ".number_format((float)$amount,2); }
'

write_raw "includes/themes.php" '<?php
function store_theme($store){ return $store["theme"] ?? $GLOBALS["config"]["stores"]["default_theme"]; }
'

write_raw "includes/router.php" '<?php
// Simple page router if needed
'

write_raw "includes/rate_limit.php" '<?php
function rate_limit_key($k){ return "rl_".$k."_".( $_SERVER["REMOTE_ADDR"] ?? "0"); }
function rate_limit_check($k, $max=60, $window=60){
  $key = rate_limit_key($k);
  $file = sys_get_temp_dir()."/$key";
  $data = ["count"=>0,"ts"=>time()];
  if (file_exists($file)) $data = json_decode(file_get_contents($file),true) ?: $data;
  if (time()-$data["ts"] > $window) $data=["count"=>0,"ts"=>time()];
  $data["count"]++;
  file_put_contents($file, json_encode($data));
  if ($data["count"]>$max) { http_response_code(429); exit("Too many requests"); }
}
'

write_raw "includes/email.php" '<?php
function send_email_local($to,$sub,$body){ /* integrate local mail() or SMTP on server */ return true; }
'

write_raw "includes/storage.php" '<?php
function storage_path($rel){ return __DIR__."/../assets/".$rel; }
'

write_raw "includes/file_upload.php" '<?php
function handle_upload($field, $destDir){
  if (!isset($_FILES[$field]) || $_FILES[$field]["error"]!==UPLOAD_ERR_OK) return [false,"No file"];
  $name = basename($_FILES[$field]["name"]);
  $ext = strtolower(pathinfo($name, PATHINFO_EXTENSION));
  $safe = bin2hex(random_bytes(8)).".$ext";
  $dir = __DIR__."/../assets/img/$destDir";
  if (!is_dir($dir)) mkdir($dir,0775,true);
  $path = "$dir/$safe";
  if (!move_uploaded_file($_FILES[$field]["tmp_name"], $path)) return [false,"Move failed"];
  return [true, "/assets/img/$destDir/$safe"];
}
'

write_raw "includes/gdpr.php" '<?php
function gdpr_user_consent_set($uid, array $consent){ $st=db()->prepare("UPDATE users SET consent_json=? WHERE id=?"); $st->execute([json_encode($consent),$uid]); }
function gdpr_forget_user($uid){
  $st = db()->prepare("UPDATE users SET deleted_at=NOW(), email=CONCAT(\"deleted+\",id,\"@example.com\"), name=\"Deleted\" WHERE id=?");
  $st->execute([$uid]);
}
'

# auth and 2FA
write_raw "includes/totp.php" '<?php
function base32_decode($b32){$alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";$b32=strtoupper($b32);$l=strlen($b32);$n=0;$j=0;$binary="";for($i=0;$i<$l;$i++){$n=$n<<5;$n=$n+strpos($alphabet,$b32[$i]);$j+=5;if($j>=8){$j-=8;$binary.=chr(($n & (0xFF<<$j))>>$j);}}return $binary;}
function totp_verify($secret,$code,$window=1,$period=30){$tm=floor(time()/$period);for($i=-$window;$i<=$window;$i++){if(hash_equals(_totp_gen($secret,$tm+$i),$code))return true;}return false;}
function _totp_gen($secret,$slice){$key=base32_decode($secret);$time=pack("N*",0).pack("N*",$slice);$hm=hash_hmac("sha1",$time,$key,true);$offset=ord(substr($hm,-1)) & 0x0F;$hash=(ord($hm[$offset]) & 0x7F)<<24 | (ord($hm[$offset+1]) & 0xFF)<<16 | (ord($hm[$offset+2]) & 0xFF)<<8 | (ord($hm[$offset+3]) & 0xFF);$v=$hash % 1000000;return str_pad($v,6,"0",STR_PAD_LEFT);}
'

write_raw "includes/auth.php" '<?php
require_once __DIR__."/totp.php";
function user_by_email($email){ $st=db()->prepare("SELECT * FROM users WHERE email=? LIMIT 1"); $st->execute([$email]); return $st->fetch(); }
function _auth_set_session($u){ $_SESSION["uid"]=$u["id"]; $_SESSION["role"]=$u["role"]; $_SESSION["store_id"]=$u["store_id"]??null; }
function user_login($email,$password){
  $u=user_by_email($email); if(!$u || !password_verify($password,$u["password_hash"])) { analytics_emit("auth.login_failed",["email"=>$email]); return [false,"Invalid credentials"]; }
  if (!empty($u["mfa_secret"])) { $_SESSION["pending_2fa_uid"]=$u["id"]; return [true,"2FA_REQUIRED"]; }
  _auth_set_session($u); analytics_emit("auth.login",["user_id"=>$u["id"]]); audit_log($u["id"],"login","User login"); return [true,"OK"];
}
function user_verify_totp($code){
  $uid=$_SESSION["pending_2fa_uid"]??null; if(!$uid) return [false,"No pending 2FA"];
  $u=db()->prepare("SELECT * FROM users WHERE id=?"); $u->execute([$uid]); $u=$u->fetch();
  if(!$u) return [false,"User missing"];
  if (totp_verify($u["mfa_secret"], $code)){ unset($_SESSION["pending_2fa_uid"]); _auth_set_session($u); return [true,"OK"]; }
  return [false,"Invalid code"];
}
function logout(){ analytics_emit("auth.logout",["user_id"=>$_SESSION["uid"]??null]); session_destroy(); }
'

write_raw "includes/notifications.php" '<?php
function notify($user_id,$title,$body,$channel="local"){
  $st=db()->prepare("INSERT INTO notifications (user_id,channel,title,body) VALUES (?,?,?,?)");
  $st->execute([$user_id,$channel,$title,$body]); return true;
}
'

# AI + search/recommend/seo/pricing/imaging
write_raw "includes/ai.php" '<?php
require_once __DIR__."/search.php";
require_once __DIR__."/recommend.php";
require_once __DIR__."/seo.php";
require_once __DIR__."/imaging.php";
require_once __DIR__."/pricing.php";
function ai_log($type, array $data){ $st=db()->prepare("INSERT INTO ai_logs (type,payload) VALUES (?,?)"); $st->execute([$type,json_encode($data)]); }
'

write_raw "includes/search.php" '<?php
function build_search_index(array $p): string {
  $blob = strtolower(($p["name"]??" ")." ".($p["description"]??" ")." ".($p["sku"]??" "));
  $blob = preg_replace("/[^a-z0-9 ]/"," ",$blob);
  $tokens = array_unique(array_filter(explode(" ", $blob)));
  return implode(" ", $tokens);
}
function popular_terms($store_id){
  $st=db()->prepare("SELECT term,COUNT(*) c FROM search_terms WHERE store_id <=> ? GROUP BY term ORDER BY c DESC LIMIT 50");
  $st->execute([$store_id]); return array_column($st->fetchAll(),"term");
}
function search_suggest(string $q, int $store_id=null): array {
  $q=mb_strtolower(trim($q));
  $params=[]; $sql="SELECT id,name,slug FROM products WHERE status='active'";
  if ($store_id){ $sql.=" AND store_id=?"; $params[]=$store_id; }
  $sql.=" AND search_index LIKE ? LIMIT 10"; $params[]="%$q%";
  $st=db()->prepare($sql); $st->execute($params); $rows=$st->fetchAll();
  if (!$rows){
    $terms=popular_terms($store_id); $closest=[];
    foreach($terms as $t){ $closest[$t]=levenshtein($q,$t); }
    asort($closest); $best=array_slice(array_keys($closest),0,5);
    ai_log("search.typo",["q"=>$q,"suggestions"=>$best]);
    return array_map(fn($t)=>["term"=>$t],$best);
  }
  ai_log("search.suggest",["q"=>$q,"count"=>count($rows)]);
  return $rows;
}
'

write_raw "includes/recommend.php" '<?php
function recommend_for_user(int $user_id=null, int $store_id=null, int $limit=8): array {
  $sql="SELECT oi2.product_id, COUNT(*) score
        FROM order_items oi
        JOIN order_items oi2 ON oi.order_id=oi2.order_id AND oi.product_id<>oi2.product_id
        ".($store_id?" JOIN products p ON p.id=oi2.product_id AND p.store_id=".intval($store_id):"")."
        GROUP BY oi2.product_id ORDER BY score DESC LIMIT ".intval($limit);
  $rows=db()->query($sql)->fetchAll();
  $ids=array_column($rows,"product_id"); if(!$ids) return [];
  $in=implode(",",array_fill(0,count($ids),"?"));
  $st=db()->prepare("SELECT * FROM products WHERE id IN ($in)"); $st->execute($ids);
  $res=$st->fetchAll(); ai_log("recommend",["store_id"=>$store_id,"user_id"=>$user_id,"count"=>count($res)]);
  return $res;
}
'

write_raw "includes/seo.php" '<?php
function seo_suggest(array $product): array {
  $title=$product["name"]." | Buy Online";
  $desc=substr(strip_tags($product["description"]??""),0,156);
  $keywords=implode(",", array_slice(explode(" ", strtolower(($product["name"]??"")." ".($product["sku"]??""))),0,8));
  $slug=strtolower(preg_replace("/[^a-z0-9]+/","-",$product["name"]??"product"));
  $s=["title"=>$title,"description"=>$desc,"keywords"=>$keywords,"slug"=>$slug];
  ai_log("seo.suggest",$s); return $s;
}
'

write_raw "includes/imaging.php" '<?php
function image_autotag(string $filepath): array {
  if (!function_exists("imagecreatefromstring")) return [];
  $im=@imagecreatefromstring(@file_get_contents($filepath)); if(!$im) return [];
  $w=imagesx($im); $h=imagesy($im); $sample=min(100,max(10,intval(($w*$h)/20000))); $colors=[];
  for($i=0;$i<$sample;$i++){
    $x=rand(0,$w-1); $y=rand(0,$h-1); $rgb=imagecolorsforindex($im, imagecolorat($im,$x,$y));
    $tag=($rgb["red"]>200&&$rgb["green"]>200&&$rgb["blue"]>200)?"light":
         (($rgb["red"]<50&&$rgb["green"]<50&&$rgb["blue"]<50)?"dark":
         ($rgb["red"]>$rgb["green"]&&$rgb["red"]>$rgb["blue"]?"red":
         ($rgb["green"]>$rgb["blue"]?"green":"blue")));
    $colors[$tag]=($colors[$tag]??0)+1;
  }
  arsort($colors); $tags=array_keys(array_slice($colors,0,3,true)); ai_log("image.autotag",["tags"=>$tags]); return $tags;
}
'

write_raw "includes/pricing.php" '<?php
function dynamic_price(float $base, array $signals=[]): float {
  $stock=$signals["stock"]??100; $views=max(1,$signals["views"]??1); $buys=$signals["buys"]??0; $conv=$buys/$views;
  $adj=1.0 + ($conv>0.05?0.05:0) - ($stock>500?0.03:0);
  return round($base*$adj, $GLOBALS["config"]["currency"]["rounding"]);
}
'

write_raw "includes/bootstrap.php" '<?php
require __DIR__."/db.php";
require __DIR__."/util.php";
require __DIR__."/csrf.php";
require __DIR__."/auth.php";
require __DIR__."/guard.php";
require __DIR__."/audit.php";
require __DIR__."/i18n.php";
require __DIR__."/currency.php";
require __DIR__."/themes.php";
require __DIR__."/modules/analytics_emitter.php";
session_name($GLOBALS["config"]["security"]["session_name"]); session_start(); csrf_init(); i18n_init();
'

# Modules
write_raw "includes/modules/analytics_emitter.php" '<?php
function analytics_emit(string $event, array $data=[]){
  if (!($GLOBALS["config"]["analytics"]["enabled"]??true)) return;
  $st=db()->prepare("INSERT INTO analytics_events (event,user_id,store_id,ip,ua,payload) VALUES (?,?,?,?,?,?)");
  $ip=$_SERVER["REMOTE_ADDR"]??""; if ($GLOBALS["config"]["analytics"]["ip_anonymize"]??false) $ip=preg_replace("/\.\d+$/",".0",$ip);
  $st->execute([$event,$_SESSION["uid"]??null,$_SESSION["store_id"]??null,$ip,$_SERVER["HTTP_USER_AGENT"]??"",json_encode($data)]);
}
'

write_raw "includes/modules/users.php" '<?php
function user_create($name,$email,$password,$role="user",$store_id=null){
  $st=db()->prepare("INSERT INTO users (name,email,password_hash,role,store_id) VALUES (?,?,?,?,?)");
  $st->execute([$name,$email,password_hash($password, PASSWORD_ARGON2ID),$role,$store_id]); return (int)db()->lastInsertId();
}
'

write_raw "includes/modules/stores.php" '<?php
function store_resolve($key,$host){
  if ($key){ $st=db()->prepare("SELECT * FROM stores WHERE slug=? OR subfolder=? LIMIT 1"); $st->execute([$key,$key]); $r=$st->fetch(); if($r) return $r; }
  $st=db()->prepare("SELECT * FROM stores WHERE domain=? LIMIT 1"); $st->execute([$host]); $r=$st->fetch(); if($r) return $r;
  return db()->query("SELECT * FROM stores ORDER BY id ASC LIMIT 1")->fetch();
}
'

write_raw "includes/modules/categories.php" '<?php
function categories_by_store($store_id){ $st=db()->prepare("SELECT * FROM categories WHERE store_id=? ORDER BY name"); $st->execute([$store_id]); return $st->fetchAll(); }
'

write_raw "includes/modules/products.php" '<?php
require_once __DIR__."/../../includes/search.php";
function product_get(int $id){
  $st=db()->prepare("SELECT p.*, s.name store_name FROM products p JOIN stores s ON s.id=p.store_id WHERE p.id=?"); $st->execute([$id]); return $st->fetch();
}
function product_list(array $filters=[], int $limit=20, int $offset=0){
  $sql="SELECT p.* FROM products p WHERE p.status=\"active\""; $params=[];
  if (!empty($filters["store_id"])){$sql.=" AND p.store_id=?"; $params[]=$filters["store_id"];}
  if (!empty($filters["category_id"])){$sql.=" AND p.category_id=?"; $params[]=$filters["category_id"];}
  if (!empty($filters["q"])){$sql.=" AND p.search_index LIKE ?"; $params[]="%".mb_strtolower($filters["q"])."%";}
  $sql.=" ORDER BY p.created_at DESC LIMIT ? OFFSET ?"; $params[]=$limit; $params[]=$offset;
  $st=db()->prepare($sql); $st->execute($params); return $st->fetchAll();
}
function product_create(array $d){
  $st=db()->prepare("INSERT INTO products (store_id,category_id,name,slug,description,price,currency,sku,inventory_qty,images,attributes,status,search_index) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)");
  $d["search_index"]=build_search_index($d);
  $st->execute([$d["store_id"],$d["category_id"]??null,$d["name"],$d["slug"],$d["description"]??"", $d["price"],$d["currency"]??"INR",$d["sku"]??null,$d["inventory_qty"]??0,json_encode($d["images"]??[]),json_encode($d["attributes"]??[]),$d["status"]??"active",$d["search_index"]]);
  $id=(int)db()->lastInsertId(); analytics_emit("product.create",["product_id"=>$id,"store_id"=>$d["store_id"]]); return $id;
}
'

write_raw "includes/modules/inventory.php" '<?php
function inventory_adjust($product_id,$change,$reason=""){
  $st=db()->prepare("INSERT INTO inventory_log (product_id,change_qty,reason) VALUES (?,?,?)"); $st->execute([$product_id,$change,$reason]);
  db()->prepare("UPDATE products SET inventory_qty=inventory_qty+? WHERE id=?")->execute([$change,$product_id]);
}
'

write_raw "includes/modules/cart.php" '<?php
require_once __DIR__."/products.php";
function cart_get(): array { return $_SESSION["cart"] ?? ["items"=>[], "currency"=>$GLOBALS["config"]["currency"]["default"], "total"=>0.0]; }
function cart_add(int $product_id, int $qty=1, array $variant=[]): array {
  $cart=cart_get(); $p=product_get($product_id); if(!$p) return $cart;
  $key=$product_id."-".md5(json_encode($variant)); $price=(float)$p["price"];
  $cart["items"][$key]=["product_id"=>$product_id,"name"=>$p["name"],"qty"=>($cart["items"][$key]["qty"]??0)+$qty,"price"=>$price,"currency"=>$p["currency"],"variant"=>$variant];
  $cart["total"]=array_sum(array_map(fn($i)=>$i["qty"]*$i["price"], $cart["items"])); $_SESSION["cart"]=$cart; analytics_emit("cart.add",["product_id"=>$product_id,"qty"=>$qty]); return $cart;
}
function cart_clear(){ $_SESSION["cart"]=["items"=>[],"currency"=>$GLOBALS["config"]["currency"]["default"],"total"=>0.0]; analytics_emit("cart.clear",[]); }
'

write_raw "includes/modules/orders.php" '<?php
require_once __DIR__."/cart.php";
require_once __DIR__."/../../includes/payments/driver_interface.php";
function order_create_from_cart(int $user_id, string $payment_driver="offline", array $shipping=[]): int {
  $cart=cart_get(); if (empty($cart["items"])) throw new Exception("Empty cart");
  $pdo=db(); $pdo->beginTransaction();
  $first=current($cart["items"]); $store_id=$first ? (db()->prepare("SELECT store_id FROM products WHERE id=?") && (function($pid){$st=db()->prepare("SELECT store_id FROM products WHERE id=?"); $st->execute([$pid]); return $st->fetchColumn();})($first["product_id"])) : null;
  $st=$pdo->prepare("INSERT INTO orders (user_id,store_id,status,total,currency,payment_driver,shipping_json) VALUES (?,?,?,?,?,?,?)");
  $st->execute([$user_id,$store_id,"pending",$cart["total"],$cart["currency"],$payment_driver,json_encode($shipping)]);
  $order_id=(int)$pdo->lastInsertId();
  $ist=$pdo->prepare("INSERT INTO order_items (order_id,product_id,qty,price,currency,variant_json) VALUES (?,?,?,?,?,?)");
  foreach($cart["items"] as $i){ $ist->execute([$order_id,$i["product_id"],$i["qty"],$i["price"],$i["currency"],json_encode($i["variant"])]); }
  $pdo->commit(); analytics_emit("order.create",["order_id"=>$order_id,"total"=>$cart["total"]]); return $order_id;
}
function order_pay(int $order_id, string $driver, array $params=[]): array {
  $drv=payments_driver($driver); $res=$drv->charge($order_id, $params);
  if ($res["ok"]){ db()->prepare("UPDATE orders SET status=\"paid\", payment_ref=? WHERE id=?")->execute([$res["ref"],$order_id]); analytics_emit("payment.success",["order_id"=>$order_id,"driver"=>get_class($drv)]); }
  else { analytics_emit("payment.fail",["order_id"=>$order_id,"driver"=>get_class($drv),"error"=>$res["error"]??""]); }
  return $res;
}
'

write_raw "includes/modules/returns.php" '<?php
function return_request($order_id,$user_id,$reason){ $st=db()->prepare("INSERT INTO returns (order_id,user_id,reason) VALUES (?,?,?)"); $st->execute([$order_id,$user_id,$reason]); return (int)db()->lastInsertId(); }
'

write_raw "includes/modules/invoices.php" '<?php
function invoice_create($order_id,$gst=null,$vat=null){ $st=db()->prepare("INSERT INTO invoices (order_id,gst_number,vat_number) VALUES (?,?,?)"); $st->execute([$order_id,$gst,$vat]); return (int)db()->lastInsertId(); }
'

write_raw "includes/modules/shipping.php" '<?php
function shipping_methods(){ return [["id"=>"standard","name"=>"Standard Shipping","price"=>0],["id"=>"express","name"=>"Express","price"=>199]]; }
'

write_raw "includes/modules/affiliate.php" '<?php
function affiliate_by_code($code){ $st=db()->prepare("SELECT * FROM affiliates WHERE code=? LIMIT 1"); $st->execute([$code]); return $st->fetch(); }
'

write_raw "includes/modules/ads.php" '<?php
function ad_slots($store_id=null,$slot="home"){ $st=db()->prepare("SELECT * FROM ads WHERE (store_id <=> ?) AND slot=? AND status=\"active\""); $st->execute([$store_id,$slot]); return $st->fetchAll(); }
'

write_raw "includes/modules/vendor.php" '<?php
function vendor_payout_create($vendor_user_id,$amount){ $st=db()->prepare("INSERT INTO vendor_payouts (vendor_user_id,amount) VALUES (?,?)"); $st->execute([$vendor_user_id,$amount]); return (int)db()->lastInsertId(); }
'

write_raw "includes/modules/pos.php" '<?php
function pos_session_open($user_id){ return true; } // local POS stubs
'

write_raw "includes/modules/b2b.php" '<?php
function b2b_quote_request($user_id,$store_id,array $items){ $st=db()->prepare("INSERT INTO b2b_quotes (user_id,store_id,items) VALUES (?,?,?)"); $st->execute([$user_id,$store_id,json_encode($items)]); return (int)db()->lastInsertId(); }
'

write_raw "includes/modules/support.php" '<?php
function ticket_create($user_id,$store_id,$subject,$body){ $st=db()->prepare("INSERT INTO support_tickets (user_id,store_id,subject) VALUES (?,?,?)"); $st->execute([$user_id,$store_id,$subject]); $tid=(int)db()->lastInsertId(); db()->prepare("INSERT INTO support_messages (ticket_id,user_id,body) VALUES (?,?,?)")->execute([$tid,$user_id,$body]); return $tid; }
'

# Payments
mkdir -p "$ROOT/includes/payments"
write_raw "includes/payments/driver_interface.php" '<?php
interface PaymentDriver { public function charge(int $order_id, array $params): array; }
function payments_driver(string $name): PaymentDriver {
  $name=strtolower($name); $file=__DIR__."/$name.php"; if (!file_exists($file)) $file=__DIR__."/offline.php"; require_once $file; $class=ucfirst($name)."Driver"; return new $class();
}
'

write_raw "includes/payments/offline.php" '<?php
require_once __DIR__."/driver_interface.php";
class OfflineDriver implements PaymentDriver {
  public function charge(int $order_id, array $params): array { return ["ok"=>true,"ref"=>"OFFLINE-".time()]; }
}
'

write_raw "includes/payments/cod.php" '<?php
require_once __DIR__."/driver_interface.php";
class CodDriver implements PaymentDriver {
  public function charge(int $order_id, array $params): array { return ["ok"=>true,"ref"=>"COD-".time()]; }
}
'

write_raw "includes/payments/bank_transfer.php" '<?php
require_once __DIR__."/driver_interface.php";
class Bank_transferDriver implements PaymentDriver {
  public function charge(int $order_id, array $params): array { return ["ok"=>true,"ref"=>"BANK-".time()]; }
}
'

for gw in razorpay paytm ccavenue instamojo stripe paypal; do
cat > "$ROOT/includes/payments/$gw.php" <<PHP
<?php
require_once __DIR__."/driver_interface.php";
class $(tr '[:lower:]' '[:upper:]' <<< ${gw:0:1})${gw:1}Driver implements PaymentDriver {
  public function charge(int \$order_id, array \$params): array {
    // Offline stub to comply with no external API calls
    return ["ok"=>true,"ref"=>"${gw^^}-OFFLINE-".time()];
  }
}
PHP
done

# Analytics
write_raw "analytics/events.php" '<?php
require __DIR__."/../includes/bootstrap.php";
header("Content-Type: application/json");
if (!($GLOBALS["config"]["analytics"]["enabled"]??true)) { echo json_encode(["ok"=>false]); exit; }
$payload=json_decode(file_get_contents("php://input"),true) ?? $_POST; $event=$payload["event"]??null; $data=$payload["data"]??[];
if (!$event){ http_response_code(400); echo json_encode(["ok"=>false,"error"=>"Missing event"]); exit; }
$st=db()->prepare("INSERT INTO analytics_events (event,user_id,store_id,ip,ua,payload) VALUES (?,?,?,?,?,?)");
$ip=$_SERVER["REMOTE_ADDR"]??""; if ($GLOBALS["config"]["analytics"]["ip_anonymize"]??false) $ip=preg_replace("/\.\d+$/",".0",$ip);
$st->execute([$event,$_SESSION["uid"]??null,$_SESSION["store_id"]??null,$ip,$_SERVER["HTTP_USER_AGENT"]??"",json_encode($data)]);
echo json_encode(["ok"=>true]);
'

write_raw "analytics/summary.php" '<?php
require __DIR__."/../includes/bootstrap.php"; require_role(["admin"]); header("Content-Type: application/json");
$range=$_GET["range"]??"7d"; $map=["24h"=>1,"7d"=>7,"30d"=>30,"90d"=>90]; $days=$map[$range] ?? 7;
$st=db()->prepare("SELECT event, DATE(created_at) d, COUNT(*) c FROM analytics_events WHERE created_at >= (NOW() - INTERVAL :days DAY) GROUP BY event, d ORDER BY d ASC");
$st->bindValue(":days",$days,PDO::PARAM_INT); $st->execute(); echo json_encode(["ok"=>true,"data"=>$st->fetchAll()]);
'

write_raw "analytics/api.php" '<?php
require __DIR__."/../includes/bootstrap.php"; require_role(["admin"]); header("Content-Type: application/json");
$q=$_GET["q"]??"top_products";
switch($q){
  case "top_products":
    $st=db()->query("SELECT p.id,p.name,SUM(oi.qty) sold FROM order_items oi JOIN products p ON p.id=oi.product_id GROUP BY p.id ORDER BY sold DESC LIMIT 10");
    echo json_encode(["ok"=>true,"data"=>$st->fetchAll()]); break;
  case "active_users":
    $st=db()->query("SELECT user_id, COUNT(*) events FROM analytics_events WHERE user_id IS NOT NULL GROUP BY user_id ORDER BY events DESC LIMIT 10");
    echo json_encode(["ok"=>true,"data"=>$st->fetchAll()]); break;
  default: echo json_encode(["ok"=>false,"error"=>"Unknown query"]);
}
'

write_raw "analytics/export.php" '<?php
require __DIR__."/../includes/bootstrap.php"; require_role(["admin"]);
header("Content-Type: text/csv"); header("Content-Disposition: attachment; filename=\"analytics_export.csv\"");
$out=fopen("php://output","w"); fputcsv($out, ["id","event","user_id","store_id","ip","ua","payload","created_at"]);
$st=db()->query("SELECT id,event,user_id,store_id,ip,ua,payload,created_at FROM analytics_events ORDER BY id DESC LIMIT 50000");
while($r=$st->fetch(PDO::FETCH_NUM)) fputcsv($out,$r); fclose($out);
'

# API
write_raw "api/product.php" '<?php
require __DIR__."/../includes/bootstrap.php"; require_once __DIR__."/../includes/modules/products.php";
header("Content-Type: application/json"); $m=$_SERVER["REQUEST_METHOD"];
if ($m==="GET"){ if (!empty($_GET["id"])) { $p=product_get((int)$_GET["id"]); analytics_emit("product.view",["product_id"=>$p["id"]??null,"uid"=>$_SESSION["uid"]??null]); json_response(["ok"=>true,"data"=>$p]); }
  $data=product_list($_GET,(int)($_GET["limit"]??20),(int)($_GET["offset"]??0)); json_response(["ok"=>true,"data"=>$data]); }
if ($m==="POST"){ require_role(["admin","vendor"]); csrf_check(); $payload=json_decode(file_get_contents("php://input"),true) ?? $_POST; $id=product_create($payload); json_response(["ok"=>true,"id"=>$id]); }
http_response_code(405); echo json_encode(["ok"=>false,"error"=>"Method not allowed"]);
'

write_raw "api/cart.php" '<?php
require __DIR__."/../includes/bootstrap.php"; require_once __DIR__."/../includes/modules/cart.php";
header("Content-Type: application/json"); $m=$_SERVER["REQUEST_METHOD"];
if ($m==="GET"){ json_response(["ok"=>true,"cart"=>cart_get()]); }
if ($m==="POST"){ csrf_check(); $d=json_decode(file_get_contents("php://input"),true) ?? $_POST; $c=cart_add((int)$d["product_id"], (int)($d["qty"]??1), $d["variant"]??[]); json_response(["ok"=>true,"cart"=>$c]); }
if ($m==="DELETE"){ cart_clear(); json_response(["ok"=>true]); }
http_response_code(405);
'

write_raw "api/search.php" '<?php
require __DIR__."/../includes/bootstrap.php"; require_once __DIR__."/../includes/search.php";
header("Content-Type: application/json"); $q=trim($_GET["q"] ?? ""); $store_id=isset($_GET["store_id"])?(int)$_GET["store_id"]:null;
$res=search_suggest($q,$store_id); $st=db()->prepare("INSERT INTO search_terms (user_id,store_id,term) VALUES (?,?,?)"); $st->execute([$_SESSION["uid"]??null,$store_id,mb_strtolower($q)]);
analytics_emit("search.query",["q"=>$q,"results"=>count($res)]); echo json_encode(["ok"=>true,"data"=>$res]);
'

write_raw "api/order.php" '<?php
require __DIR__."/../includes/bootstrap.php"; require_once __DIR__."/../includes/modules/orders.php";
header("Content-Type: application/json"); require_login(); $m=$_SERVER["REQUEST_METHOD"];
if ($m==="POST"){ csrf_check(); $payload=json_decode(file_get_contents("php://input"),true) ?? $_POST; $driver=$payload["driver"] ?? $GLOBALS["config"]["payments"]["default_driver"]; $oid=order_create_from_cart((int)$_SESSION["uid"], $driver, $payload["shipping"] ?? []); $pay=order_pay($oid,$driver,[]); json_response(["ok"=>true,"order_id"=>$oid,"payment"=>$pay]); }
http_response_code(405);
'

# Stub remaining API endpoints
for f in auth returns payments affiliate ads vendor b2b support notifications store user; do
  write_raw "api/$f.php" "<?php require __DIR__.'/../includes/bootstrap.php'; header('Content-Type: application/json'); echo json_encode(['ok'=>true,'msg'=>'$f endpoint stub']);"
done

# Store frontend
write_raw "store/index.php" '<?php
require __DIR__."/../includes/bootstrap.php"; require_once __DIR__."/../includes/modules/stores.php"; require_once __DIR__."/../includes/modules/products.php";
$store_key=$_GET["store"] ?? null; $store=store_resolve($store_key, $_SERVER["HTTP_HOST"] ?? ""); $_SESSION["store_id"]=$store["id"] ?? null;
$theme=store_theme($store); $featured=product_list(["store_id"=>$store["id"]??null],12,0);
include __DIR__."/../templates/$theme/header.php";
include __DIR__."/../templates/$theme/home.php";
include __DIR__."/../templates/$theme/footer.php";
'

write_raw "store/product.php" '<?php
require __DIR__."/../includes/bootstrap.php"; require_once __DIR__."/../includes/modules/products.php";
$id=(int)($_GET["id"]??0); $p=product_get($id); if(!$p){ http_response_code(404); exit("Not found"); }
?><!DOCTYPE html><html><head><meta charset="utf-8"><title><?= htmlspecialchars($p["name"]) ?></title><link rel="stylesheet" href="/ecomx/assets/css/store.css"></head><body>
<h1><?= htmlspecialchars($p["name"]) ?></h1>
<p><?= htmlspecialchars($p["currency"]) ?> <?= number_format($p["price"],2) ?></p>
<form method="post" action="/ecomx/store/cart.php">
  <input type="hidden" name="csrf" value="<?= csrf_token() ?>">
  <input type="hidden" name="product_id" value="<?= (int)$p["id"] ?>">
  <button type="submit">Add to Cart</button>
</form>
</body></html>
'

write_raw "store/cart.php" '<?php
require __DIR__."/../includes/bootstrap.php"; require_once __DIR__."/../includes/modules/cart.php";
if (($_SERVER["REQUEST_METHOD"]??"GET")==="POST"){ csrf_check(); $pid=(int)($_POST["product_id"]??0); if($pid) cart_add($pid,1,[]); redirect("/ecomx/store/cart.php"); }
$cart=cart_get();
?><!DOCTYPE html><html><head><meta charset="utf-8"><title>Cart</title><link rel="stylesheet" href="/ecomx/assets/css/store.css"></head><body>
<h1>Cart</h1>
<?php if(!$cart["items"]): ?><p>Cart is empty</p><?php else: ?>
<ul>
<?php foreach($cart["items"] as $i): ?>
<li><?= htmlspecialchars($i["name"]) ?> x <?= (int)$i["qty"] ?> — <?= htmlspecialchars($i["currency"]) ?> <?= number_format($i["price"],2) ?></li>
<?php endforeach; ?>
</ul>
<p>Total: <?= htmlspecialchars($cart["currency"]) ?> <?= number_format($cart["total"],2) ?></p>
<form action="/ecomx/store/checkout.php" method="post">
  <input type="hidden" name="csrf" value="<?= csrf_token() ?>">
  <button type="submit">Checkout</button>
</form>
<?php endif; ?>
</body></html>
'

write_raw "store/checkout.php" '<?php
require __DIR__."/../includes/bootstrap.php"; require_once __DIR__."/../includes/modules/orders.php"; require_login();
if (($_SERVER["REQUEST_METHOD"]??"GET")==="POST"){ csrf_check(); $oid=order_create_from_cart((int)$_SESSION["uid"], "offline", []); $pay=order_pay($oid,"offline",[]); redirect("/ecomx/store/order_success.php?id=".$oid); }
?><!DOCTYPE html><html><head><meta charset="utf-8"><title>Checkout</title></head><body><h1>Checkout</h1><form method="post"><input type="hidden" name="csrf" value="<?= csrf_token() ?>"><button type="submit">Pay Offline</button></form></body></html>
'

write_raw "store/order_success.php" '<?php
require __DIR__."/../includes/bootstrap.php"; $id=(int)($_GET["id"]??0);
?><!DOCTYPE html><html><head><meta charset="utf-8"><title>Order Success</title></head><body><h1>Order #<?= $id ?> placed.</h1><a href="/ecomx/store/">Back to Home</a></body></html>
'

for f in category search returns pages faq; do
  write_raw "store/$f.php" "<?php require __DIR__.'/../includes/bootstrap.php'; echo '<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>$f</title></head><body><h1>$f page</h1></body></html>';"
done

# Admin/User/Vendor/Affiliate/B2B stubs
for dir in admin user vendor affiliate b2b; do mkdir -p "$ROOT/$dir"; done

write_raw "admin/index.php" '<?php require __DIR__."/../includes/bootstrap.php"; require_role(["admin"]); redirect("/ecomx/admin/dashboard.php");'
write_raw "admin/dashboard.php" '<?php require __DIR__."/../includes/bootstrap.php"; require_role(["admin"]); ?><!DOCTYPE html><html><head><meta charset="utf-8"><title>Admin Dashboard</title><link rel="stylesheet" href="/ecomx/assets/css/admin.css"><script src="/ecomx/assets/js/charts.js"></script></head><body><h1>Dashboard</h1><canvas id="sales" width="600" height="200"></canvas><script>fetch("/ecomx/analytics/summary.php?range=7d").then(r=>r.json()).then(d=>drawMiniChart("sales", d.data.map(x=>x.c)));</script></body></html>'
for f in roles users stores products orders returns payouts affiliates ads analytics ai support settings compliance logs; do
  write_raw "admin/$f.php" "<?php require __DIR__.'/../includes/bootstrap.php'; require_role(['admin']); echo '<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>Admin - $f</title></head><body><h1>Admin: $f</h1></body></html>';"
done

for f in login register profile dashboard orders invoices support notifications; do
  write_raw "user/$f.php" "<?php require __DIR__.'/../includes/bootstrap.php'; echo '<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>User - $f</title></head><body><h1>User: $f</h1></body></html>';"
done

for f in dashboard products inventory orders payouts analytics settings; do
  write_raw "vendor/$f.php" "<?php require __DIR__.'/../includes/bootstrap.php'; require_role(['vendor','admin']); echo '<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>Vendor - $f</title></head><body><h1>Vendor: $f</h1></body></html>';"
done

for f in dashboard links earnings campaigns analytics; do
  write_raw "affiliate/$f.php" "<?php require __DIR__.'/../includes/bootstrap.php'; require_role(['affiliate','admin']); echo '<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>Affiliate - $f</title></head><body><h1>Affiliate: $f</h1></body></html>';"
done

for f in dashboard quotes deals pricing; do
  write_raw "b2b/$f.php" "<?php require __DIR__.'/../includes/bootstrap.php'; require_role(['admin','vendor']); echo '<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>B2B - $f</title></head><body><h1>B2B: $f</h1></body></html>';"
done

# API auth (simple demo form)
write_raw "api/auth.php" '<?php
require __DIR__."/../includes/bootstrap.php"; header("Content-Type: application/json"); $m=$_SERVER["REQUEST_METHOD"];
if ($m==="POST"){
  csrf_check();
  $payload=json_decode(file_get_contents("php://input"),true) ?? $_POST;
  [$ok,$msg]=user_login(trim($payload["email"]??""), (string)($payload["password"]??""));
  echo json_encode(["ok"=>$ok,"msg"=>$msg]); exit;
}
http_response_code(405);
'

# Templates
mkdir -p "$ROOT/templates/default/blocks"
write_raw "templates/default/header.php" '<?php $store_name=htmlspecialchars($store["name"] ?? "EcomX"); ?><!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title><?= $store_name ?></title><link rel="stylesheet" href="/ecomx/assets/css/base.css"><link rel="stylesheet" href="/ecomx/assets/css/store.css"><script src="/ecomx/assets/js/app.js" defer></script></head><body><header class="site-header"><div class="logo"><a href="/ecomx/store/<?= htmlspecialchars($store["slug"] ?? ""); ?>"><?= $store_name ?></a></div><form class="search" action="/ecomx/store/search.php" method="get"><input type="text" name="q" id="q" placeholder="Search products" autocomplete="off"><button type="submit">Search</button></form><nav><a href="/ecomx/user/register.php" class="btn">Create Site</a><a href="/ecomx/user/login.php">Login</a><a href="/ecomx/store/cart.php">Cart</a></nav></header><main>'
write_raw "templates/default/home.php" '<?php ?><section class="hero"><?php include __DIR__."/blocks/hero.php"; ?></section><section class="grid"><h2>Featured</h2><div class="products"><?php foreach (($featured??[]) as $p): ?><div class="card"><img src="/ecomx/assets/img/placeholders/product.png" alt=""><h3><?= htmlspecialchars($p["name"]) ?></h3><p><?= htmlspecialchars($p["currency"]) ?> <?= number_format($p["price"],2) ?></p><a class="btn" href="/ecomx/store/product.php?id=<?= (int)$p["id"] ?>">View</a></div><?php endforeach; ?></div></section><section class="recommend"><h2>You may like</h2><div class="products"><?php foreach (recommend_for_user($_SESSION["uid"]??null,$store["id"]??null,8) as $p): ?><div class="card"><h3><?= htmlspecialchars($p["name"]) ?></h3><a href="/ecomx/store/product.php?id=<?= (int)$p["id"] ?>">View</a></div><?php endforeach; ?></div></section>'
write_raw "templates/default/footer.php" '<?php ?></main><footer class="site-footer"><div>© <?= date("Y") ?> <?= htmlspecialchars($store["name"] ?? "EcomX") ?></div></footer></body></html>'
write_raw "templates/default/blocks/hero.php" '<div class="hero-inner"><h1>Welcome to <?= htmlspecialchars($store["name"] ?? "EcomX") ?></h1><p>Build your brand. Sell anything.</p></div>'
write_raw "templates/default/blocks/products_grid.php" '<div><!-- products grid placeholder --></div>'
write_raw "templates/default/blocks/recommend.php" '<div><!-- recommend block --></div>'
write_raw "templates/default/blocks/ads.php" '<div><!-- ads block --></div>'
mkdir -p "$ROOT/templates/admin"
write_raw "templates/admin/layout.php" '<div class="admin-layout"><header>Admin</header><main><?= $content ?? "" ?></main></div>'
write_raw "templates/admin/widgets.php" '<?php /* widgets */ ?>'
write_raw "templates/admin/charts.php" '<?php /* charts tpl */ ?>'

# Assets
mkdir -p "$ROOT/assets/css" "$ROOT/assets/js" "$ROOT/assets/img/logos" "$ROOT/assets/img/uploads" "$ROOT/assets/img/placeholders" "$ROOT/assets/charts" "$ROOT/assets/fonts"
write_raw "assets/css/base.css" ':root{--primary:#0f6;--text:#111;--muted:#666;--bg:#fff}*{box-sizing:border-box}body{font-family:system-ui,Segoe UI,Arial,sans-serif;color:var(--text);background:var(--bg);margin:0}.site-header{display:flex;gap:1rem;align-items:center;padding:.75rem 1rem;border-bottom:1px solid #eee}.site-header .btn{background:var(--primary);color:#000;padding:.5rem .75rem;border-radius:6px;text-decoration:none}.products{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:1rem}.card{border:1px solid #eee;padding:.75rem;border-radius:8px}.btn{background:#111;color:#fff;padding:.5rem .75rem;border-radius:6px;text-decoration:none}'
write_raw "assets/css/admin.css" 'body{font-family:system-ui}.widget{border:1px solid #eee;padding:1rem;margin:.5rem;border-radius:8px}'
write_raw "assets/css/store.css" '.hero-inner{padding:2rem;background:#f6fff9;border-bottom:1px solid #e0f5e8}'

write_raw "assets/js/app.js" 'document.addEventListener("DOMContentLoaded",()=>{const q=document.getElementById("q");if(q){let t;q.addEventListener("input",e=>{clearTimeout(t);t=setTimeout(async()=>{const r=await fetch(`/ecomx/api/search.php?q=${encodeURIComponent(q.value)}`).then(x=>x.json());console.log("suggest",r.data);},200);});}});'
write_raw "assets/js/search.js" '// search helpers'
write_raw "assets/js/validate.js" '// form validation helpers'
write_raw "assets/js/ai.js" '// local AI helpers'
write_raw "assets/js/charts.js" 'function drawMiniChart(id,data){const c=document.getElementById(id);if(!c)return;const ctx=c.getContext("2d");ctx.clearRect(0,0,c.width,c.height);ctx.strokeStyle="#0a0";ctx.beginPath();const max=Math.max(1,...data);data.forEach((v,i)=>{const x=i*(c.width/(data.length-1||1));const y=c.height-(v/max)*c.height; i?ctx.lineTo(x,y):ctx.moveTo(x,y);});ctx.stroke();}'
write_raw "assets/js/zxing.min.js" '/* minimal placeholder for barcode/QR local reader - integrate full ZXing if needed */'
write_raw "assets/img/placeholders/product.png" '' # empty placeholder

# API directory done

# schema.sql
cat > "$ROOT/schema.sql" <<'SQL'
CREATE TABLE users (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  store_id BIGINT NULL,
  role ENUM('admin','user','vendor','affiliate') NOT NULL DEFAULT 'user',
  name VARCHAR(120) NOT NULL,
  email