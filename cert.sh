#!/bin/bash


# ==============================
# 颜色
# ==============================
green="\033[32m"
red="\033[31m"
plain="\033[0m"

LOGI() { echo -e "${green}[INFO] $1${plain}"; }
LOGE() { echo -e "${red}[ERROR] $1${plain}"; }


# ==============================
# 全局检测
# ==============================

check_acme() {
  [ -x "$HOME/.acme.sh/acme.sh" ]
}

# ==============================
# 安装 acme.sh（检测）
# ==============================
install_acme() {

  if check_acme; then
    LOGE "acme.sh 已存在，自动退出安装"
    return 0
  fi

  curl -fsSL https://get.acme.sh | sh

  if [ $? -ne 0 ]; then
    LOGE "安装失败"
    return 1
  fi

  export PATH="$HOME/.acme.sh:$PATH"
  $HOME/.acme.sh/acme.sh --set-default-ca --server letsencrypt

  LOGI "安装成功"
  
}

# ==============================
# 卸载 acme.sh（检测）
# ==============================
uninstall_acme() {

  if ! check_acme; then
    LOGI "acme.sh 不存在，无需卸载"
    return 0
  fi

  $HOME/.acme.sh/acme.sh --uninstall

  LOGI "删除安装目录: $HOME/.acme.sh"
  rm -rf "$HOME/.acme.sh"

  LOGI "删除证书目录: $HOME/cert"
  rm -rf "$HOME/cert"

  LOGI "卸载完成"
  

}

# ==============================
# HTTP-01（80端口证书）
# ==============================
ssl_http() {

  # 80端口检测 先判断是否被占用
    if ss -lntp | awk '$4 ~ /:80$/' | grep -q .; then
      LOGE "80端口被以下进程所占用，请先关闭进程或相关服务"
      echo "========================================="
      echo 
      ss -lntp | awk '$4 ~ /:80$/ {print $NF}'
      echo 
      echo "========================================="
      return 1
    fi

    if ! check_acme; then
      LOGE "acme.sh 不存在，请先安装"
      return 1
    fi

  local domain=""

  while true; do
    read -rp " 请输入域名 (输入 0 或 q 退出): " domain
    domain="${domain// /}" # 检查是否输入为空
    
  # 中断返回
    if [[ "$domain" == "0" || "$domain" == "q" || "$domain" == "Q" ]]; then
      LOGI "已取消操作"
      return
    fi

    if [[ -z "$domain" ]]; then
      LOGE "域名输入不能为空，请重新输入"
      continue
    fi
    break
  done
      LOGI "输入的域名: $domain"
      
      read -p "按回车继续..."
   
  # 检测证书是否重复申请
    if $HOME/.acme.sh/acme.sh --list | awk '{print $1}' | grep -Fxq "$domain"; then
      LOGE "${domain} 已经存在，请检查输入域名，或检查 $HOME/.acme.sh/ 目录下同名文件，避免重复申请，如果想重新申请，请删除此文件再次尝试即可"
      return
    fi
  # 选择证书颁发 CA 机构
    clear
    echo "============选择证书颁发CA机构============="
    echo
    echo "1. Let's Encrypt（有效期 90天）"
    echo
    echo "2. ZeroSSL（有效期 90天，首次申请需要邮箱注册账户）"
    echo
    echo "3. 退出"
    echo
    echo "==========================================="
    local ca_choice=""
    local SELECTED_CA=""
    while true; do
        read -rp "请输入数字选项: " ca_choice
        ca_choice="${ca_choice// /}"  # 去掉空格

        case "$ca_choice" in
            1)
                SELECTED_CA="letsencrypt"
                break
                ;;
            2)
                SELECTED_CA="zerossl"
                # 选择是否注册邮箱
                clear
                echo
                echo "1. 注册 ZeroSSL 账户 (首次申请选择此项)"
                echo
                echo "2. 跳过注册 (非首次申请选择此项)"
                echo
                echo "3. 退出"
                echo

                local zerossl_choice=""
                while true; do
                read -rp "请输入数字选项: " zerossl_choice
                zerossl_choice="${zerossl_choice// /}"  # 去掉空格

                case "$zerossl_choice" in
                    1)
                       local email=""
                       clear
                       while true; do
                       read -rp "请输入你的邮箱: " email
                       email="${email// /}"
                       if [[ -z "$email" ]]; then
                          LOGE "邮箱不能为空，请重新输入"
                          continue
                       fi
                        break
                       done
                        $HOME/.acme.sh/acme.sh --register-account -m "$email" --server zerossl
                        if [ $? -ne 0 ]; then
                           LOGE "注册失败"
                           return
                        fi
                        ;;
                    2)
                        LOGI "已跳过账户注册"
                        break
                        ;;
                    3)
                        LOGI "已选择退出"
                        return
                        ;;
                    *)
                        LOGE "无效输入，请重新输入"
                        ;;
                    esac
                done
                ;;
            3)
                LOGI "已选择退出"
                return
                ;;
            *)
                LOGE "无效输入，请重新输入"
                ;;
        esac
    done

        LOGI "你选择的 CA 是: $SELECTED_CA"

  # 设置CA
  $HOME/.acme.sh/acme.sh --set-default-ca --server "$SELECTED_CA" --force

  # 申请证书
  $HOME/.acme.sh/acme.sh --issue -d "$domain" --standalone --force
    if [ $? -ne 0 ]; then
       LOGE "申请失败"
       return
    fi
  
  # 安装证书到指定目录
  mkdir -p "$HOME/cert/$domain"
  $HOME/.acme.sh/acme.sh --install-cert -d "$domain" \
      --key-file "$HOME/cert/$domain/privkey.pem" \
      --fullchain-file "$HOME/cert/$domain/fullchain.pem"

  LOGI "证书安装路径： $HOME/cert/$domain"
  
}

# ==============================
# Cloudflare DNS-01
# ==============================
ssl_cf() {

    if ! check_acme; then
      LOGE "acme.sh 不存在，请先安装 "
      return 1
    fi

   # --- 检查已有 CF_Token ---
    local existing_cf_token=""
    local acme_conf="$HOME/.acme.sh/account.conf"
    local cf_token=""
    
   # 读取文件中 CF_Token 的值
    if [[ -f "$acme_conf" ]]; then
        existing_cf_token=$(grep -E "^SAVED_CF_Token=" "$acme_conf" | sed -E "s/^SAVED_CF_Token='(.*)'$/\1/")
    fi
   # 判断是否有已有 Token
   if [[ -n "$existing_cf_token" ]]; then
        LOGI "检测到已有 Cloudflare API Token: $existing_cf_token"
    
      while true; do
        read -rp "是否使用当前 Cloudflare API Token ？( y/n ，退出 0/q ): " choice
        choice="${choice,,}"  # 转为小写

        case "$choice" in
            y)
                cf_token="$existing_cf_token"
                break
                ;;
            n)  
                # 跳出循环，输入新 Token
                break
                ;;
            0|q)
                LOGI "已取消操作"
                return
                ;;
            *)
                LOGE "无效输入，输入 y/n ，退出输入 0/q "
                ;;
        esac
        done
    fi
      # 如果没有已有 Token，或者选择输入新 Token
      clear
      while [[ -z "$cf_token" ]]; do
            read -rp "请输入 Cloudflare API Token (输入 0 或 q 退出): " cf_token
            cf_token="${cf_token// /}"  # 去掉空格
            if [[ "$cf_token" =~ ^(0|q|Q)$ ]]; then
                LOGI "已取消操作"
                return
            fi
            if [[ -z "$cf_token" ]]; then
                LOGE "Cloudflare API Token 不能为空，请重新输入"    
            fi
      done

    
    export CF_Token="$cf_token"
    
    LOGI "Cloudflare API Token: $CF_Token"
    
    read -p "按回车继续..."
  
  # 选择证书颁发 CA 机构
    clear
    echo "============选择证书颁发CA机构============="
    echo
    echo "1. Let's Encrypt（有效期 90天）"
    echo
    echo "2. ZeroSSL（有效期 90天，首次申请需要邮箱注册账户）"
    echo
    echo "3. 退出"
    echo
    echo "==========================================="
    local ca_choice=""
    local SELECTED_CA=""
    while true; do
        read -rp "请输入数字选项: " ca_choice
        ca_choice="${ca_choice// /}"  # 去掉空格

        case "$ca_choice" in
            1)
                SELECTED_CA="letsencrypt"
                break
                ;;
            2)
                SELECTED_CA="zerossl"
                # 选择是否注册邮箱
                clear
                echo
                echo "1. 注册 ZeroSSL 账户 (首次申请选择此项)"
                echo
                echo "2. 跳过注册 (非首次申请选择此项)"
                echo
                echo "3. 退出"
                echo

                local zerossl_choice=""
                while true; do
                read -rp "请输入数字选项: " zerossl_choice
                zerossl_choice="${zerossl_choice// /}"  # 去掉空格

                case "$zerossl_choice" in
                    1)
                       local email=""
                       clear
                       while true; do
                       read -rp "请输入你的邮箱: " email
                       email="${email// /}"
                       if [[ -z "$email" ]]; then
                          LOGE "邮箱不能为空，请重新输入"
                          continue
                       fi
                        break
                       done
                        $HOME/.acme.sh/acme.sh --register-account -m "$email" --server zerossl
                        if [ $? -ne 0 ]; then
                           LOGE "注册失败"
                           return
                        fi
                        ;;
                    2)
                        LOGI "已跳过账户注册"
                        break
                        ;;
                    3)
                        LOGI "已选择退出"
                        return
                        ;;
                    *)
                        LOGE "无效输入，请重新输入"
                        ;;
                    esac
                done
                ;;
            3)
                LOGI "已选择退出"
                return
                ;;
            *)
                LOGE "无效输入，请重新输入"
                ;;
        esac
    done

        LOGI "你选择的 CA 是: $SELECTED_CA"

  # 设置CA
  $HOME/.acme.sh/acme.sh --set-default-ca --server "$SELECTED_CA" --force
    
  # --- 选择证书类型 ---
  local cert_type=""
  clear
  while true; do
    echo
    echo "================ 选择证书类型 ================"
    echo 
    echo "1. 单域名证书 (标准) "
    echo
    echo "2. 二级通配符域名证书 (仅支持一级域名申请) "
    echo
    echo "3. 退出"
    echo
    echo "=============================================="
    echo 
    read -rp "请输入数字选项: " cert_type
    cert_type="${cert_type// /}"

    if [[ "$cert_type" != "1" && "$cert_type" != "2" && "$cert_type" != "3" ]]; then
      LOGE "输入错误，请输入 1、2 或 3"
      continue
    fi

    if [[ "$cert_type" == "3" ]]; then
      LOGI "已选择退出"
      return 0
    fi

    break
  done

  # --- 单域名证书 ---
  if [[ "$cert_type" == "1" ]]; then
    local domain=""
    clear
    while true; do
      read -rp "请输入域名 ( 0 或 q 退出 ): " domain
      domain="${domain// /}"
    # 退出判断
    if [[ "$domain" =~ ^(0|q|Q)$ ]]; then
        LOGI "已取消操作"
        return
    fi
    # 非空检查
    if [[ -z "$domain" ]]; then
        LOGE "域名不能为空，请重新输入"
        continue
    fi
        # 如果通过以上检查，跳出循环
    break
 done
    
      LOGI "输入的域名：$domain"
      
  # 检测证书是否重复申请
      if $HOME/.acme.sh/acme.sh --list | awk '{print $1}' | grep -Fxq "$domain"; then
        LOGE "${domain} 已经存在，请检查输入域名，或检查 $HOME/.acme.sh/ 目录下同名文件，避免重复申请，如果想重新申请，请删除此文件再次尝试即可"
        return
      fi
        LOGI "申请单域名证书: $domain"
  $HOME/.acme.sh/acme.sh --issue \
      --dns dns_cf \
      -d "$domain" \
      --force

      if [ $? -ne 0 ]; then
        LOGE "单域名证书申请失败"
        return
      fi
  # 安装证书到指定目录
  mkdir -p "$HOME/cert/$domain"
  $HOME/.acme.sh/acme.sh --install-cert -d "$domain" \
      --key-file "$HOME/cert/$domain/privkey.pem" \
      --fullchain-file "$HOME/cert/$domain/fullchain.pem"
  
  LOGI "证书安装路径： $HOME/cert/$domain"
  
  fi
  
  # --- 通配符证书 ---
  if [[ "$cert_type" == "2" ]]; then
    local domain=""
    clear
    while true; do
    read -rp "请输入域名 (例如 example.com, 仅一级域名, 输入 0 或 q 退出): " domain
    domain="${domain// /}"  # 去掉空格

    # 退出判断
    if [[ "$domain" =~ ^(0|q|Q)$ ]]; then
        LOGI "已取消操作"
        return
    fi

    # 非空检查
    if [[ -z "$domain" ]]; then
        LOGE "域名不能为空，请重新输入"
        continue
    fi

    # 检测是否为一级域名（必须只有两个段）
    if [[ $(awk -F. '{print NF}' <<< "$domain") -ne 2 ]]; then
        LOGE "输入错误：通配符证书必须输入一级域名（例如 example.com），请重新输入"
        continue
    fi

    # 如果通过以上检查，跳出循环
    break
done
      LOGI "输入的域名：$domain"
  # 检测证书是否重复申请
      if $HOME/.acme.sh/acme.sh --list | awk '{print $1}' | grep -Fxq "$domain"; then
        LOGE "${domain} 已经存在，请检查输入域名，或检查 $HOME/.acme.sh/ 目录下同名文件，避免重复申请，如果想重新申请，请删除此文件再次尝试即可"
        return
      fi
        LOGI "二级通配符证书申请: $domain + *.$domain"
  # 申请证书
    $HOME/.acme.sh/acme.sh --issue \
        --dns dns_cf \
        -d "$domain" \
        -d "*.$domain" \
        --force

      if [ $? -ne 0 ]; then
        LOGE "二级通配符证书申请失败"
        return
      fi
  
  # 安装证书到指定目录
  mkdir -p "$HOME/cert/$domain"
  $HOME/.acme.sh/acme.sh --install-cert -d "$domain" \
      --key-file "$HOME/cert/$domain/privkey.pem" \
      --fullchain-file "$HOME/cert/$domain/fullchain.pem"
  
  LOGI "证书安装路径： $HOME/cert/$domain"
 
  fi
}

# ==============================
# 吊销证书
# ==============================
revoke() {

  if ! check_acme; then
    LOGE "acme.sh 不存在，请先安装"
    return 1
  fi

  echo "==================证书列表======================="

  # 读取目录
  mapfile -t domains < <(ls "$HOME/cert" 2>/dev/null)

  if [ ${#domains[@]} -eq 0 ]; then
    LOGE "没有可吊销的证书"
    return 1
  fi

  # 打印编号
  for i in "${!domains[@]}"; do
    echo "$((i + 1)). ${domains[$i]}"
  done

  echo "0. 返回"
  echo "================================================"

  local choice
  local domain

  while true; do
    read -rp "请输入编号: " choice

    #  返回
    if [[ "$choice" == "0" ]]; then
      LOGI "已选择返回"
      return
    fi

    #  必须是数字
    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
      LOGE "请输入数字"
      continue
    fi

    #  范围判断
    if ((choice < 1 || choice > ${#domains[@]})); then
      LOGE "编号超出范围"
      continue
    fi

    domain="${domains[$((choice - 1))]}"
    break
  done

  LOGI "你选择的域名: $domain"

  # ==============================
  # 吊销证书
  # ==============================

  $HOME/.acme.sh/acme.sh --revoke -d "$domain"

  if [ $? -ne 0 ]; then
    LOGE "吊销失败"
    return
  fi

  # ==============================
  # 删除目录
  # ==============================

  dir1="$HOME/.acme.sh/${domain}_ecc"
  dir2="$HOME/.acme.sh/${domain}"
  dir3="$HOME/cert/$domain"

  echo "发现目录："
  [ -d "$dir1" ] && echo " - $dir1"
  [ -d "$dir2" ] && echo " - $dir2"
  [ -d "$dir3" ] && echo " - $dir3"

  echo ""
  read -rp "确认删除这些目录？(y/n): " confirm

  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    rm -rf "$dir1" "$dir2" "$dir3"
    LOGI "已删除"
  else
    LOGI "已取消删除"
  fi

  LOGI "吊销完成"
}

# ==============================
# 续期证书
# ==============================
renew() {

  if ! check_acme; then
    LOGE "acme.sh 不存在，请先安装"
    return 1
  fi

  echo "==================证书列表======================="

  mapfile -t domains < <(ls "$HOME/cert" 2>/dev/null)

  if [ ${#domains[@]} -eq 0 ]; then
    LOGE "没有可续期的证书"
    return 1
  fi

  for i in "${!domains[@]}"; do
    echo "$((i + 1)). ${domains[$i]}"
  done

  echo "0. 返回"
  echo "================================================"

  local choice
  local domain

  while true; do
    read -rp "请输入编号: " choice

    #  0 返回
    if [[ "$choice" == "0" ]]; then
      LOGI "已选择返回"
      return
    fi

    #  必须是数字
    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
      LOGE "请输入数字"
      continue
    fi

    #  范围判断
    if ((choice < 1 || choice > ${#domains[@]})); then
      LOGE "编号超出范围"
      continue
    fi

    domain="${domains[$((choice - 1))]}"
    break
  done

  LOGI "你选择的域名: $domain"

  # ==============================
  # 续期逻辑
  # ==============================

  $HOME/.acme.sh/acme.sh --renew -d "$domain" --force

  if [ $? -ne 0 ]; then
    LOGE "续期失败"
    return
  fi

  LOGI "安装新证书"

  mkdir -p "$HOME/cert/$domain"

  $HOME/.acme.sh/acme.sh --install-cert -d "$domain" \
    --key-file "$HOME/cert/$domain/privkey.pem" \
    --fullchain-file "$HOME/cert/$domain/fullchain.pem"

  LOGI "续期完成"

}

# ==============================
# 证书信息查询
# ==============================
cert_info() {
  
  echo "===============证书信息==================="
  echo
  echo 
  $HOME/.acme.sh/acme.sh --list
  echo 
  echo 
  echo "=========================================="
  
}

# ==============================
# 修改cf_token
# ==============================
change_cf_token() {
    if ! check_acme; then
        LOGE "acme.sh 不存在，请先安装"
        return 1
    fi

    local conf_file="$HOME/.acme.sh/account.conf"
    local current_token=""

    # 读取当前保存的 Cloudflare API Token
    if [[ -f "$conf_file" ]]; then
        current_token=$(grep -E "^SAVED_CF_Token=" "$conf_file" | sed -E "s/^SAVED_CF_Token='(.*)'$/\1/")
    fi

    if [[ -n "$current_token" ]]; then
    LOGI "当前保存的 Cloudflare API Token: $current_token"
    
    while true; do
        read -rp "是否要修改 Cloudflare API Token？(y/n): " confirm
        confirm="${confirm,,}"  # 转小写

        if [[ "$confirm" == "y" ]]; then
            LOGI "准备修改 Cloudflare API Token"
            break  # 跳出循环，继续修改流程
        elif [[ "$confirm" == "n" ]]; then
            LOGI "未修改 Cloudflare API Token"
            return  # 直接返回，不修改
        else
            LOGE "无效输入，请输入 y 或 n "
        fi
    done
else
    LOGI "Cloudflare API Token 不存在"
fi

    local cf_token=""

    while true; do
        read -rp "请输入新的 Cloudflare API Token（输入 0 或 q 退出）: " cf_token

        # 去掉空格
        cf_token="${cf_token// /}"

        # 中断返回
        if [[ "$cf_token" == "0" || "$cf_token" == "q" ]]; then
            LOGI "已取消操作"
            return
        fi

        # 空值校验
        if [[ -z "$cf_token" ]]; then
            LOGE "Cloudflare API Token 输入不能为空，请重新输入"
            continue
        fi

        break
    done

    LOGI "Cloudflare API Token: $cf_token"

    # 确保配置文件存在
    touch "$conf_file"

    # 删除旧的
    sed -i '/SAVED_CF_Token/d' "$conf_file"

    # 写入新的
    echo "SAVED_CF_Token='$cf_token'" >>"$conf_file"
    LOGI "更新完成"
}
# ==============================
# SSL菜单
# ==============================
ssl_menu() {

  while true; do
    clear
    echo "=========================================="
    echo "=============  SSL Manager  =============="
    echo "=========================================="
    echo
    echo "1. 申请证书 (80端口) 模式"
    echo
    echo "2. 申请证书 Cloudflare 模式"
    echo
    echo "3. 吊销证书 Revoke"
    echo
    echo "4. 续期证书 Renew"
    echo
    echo "5. 已申请证书信息"
    echo
    echo "6. 更新密钥 Cloudflare API Token"
    echo
    echo "0. 返回"
    echo
    echo "=========================================="

    read -rp "请输入数字选项: " c

    case "$c" in
      1)
        clear
        ssl_http
        ;;
      2)
        clear
        ssl_cf
        ;;
      3)
        clear
        revoke
        ;;
      4)
        clear
        renew
        ;;
      5)
        clear
        cert_info
        ;;
      6)
        clear
        change_cf_token
        ;;
      0)
        return
        ;;
      *)
        LOGE "无效输入，请重新输入"
        ;;
    esac
    read -p "按回车继续..."
  done
}

# ==============================
# 主菜单
# ==============================
menu() {

  while true; do
    clear
    echo "=============================="
    echo "===== ACME 全能证书工具 ======"
    echo "=============================="
    echo
    echo "1. 安装 Install acme.sh"
    echo
    echo "2. 证书管理 SSL Manager"
    echo
    echo "3. 卸载 Uninstall acme.sh"
    echo
    echo "0. 退出 Exit"
    echo
    echo "=============================="

    read -rp "请输入数字选项: " n

    case "$n" in
      1)
        clear
        install_acme
        ;;
      2)
        ssl_menu
        ;;
      3)
        clear
        uninstall_acme
        ;;
      0)
        clear
        exit 0
        ;;
      *)
        LOGE "无效输入，请重新输入"
        ;;
    esac
    read -p "按回车继续..."
  done
}

# ==============================
# start
# ==============================
menu
