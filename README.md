# 使用说明


集成acme安装卸载以及证书管理脚本


适用 debian，ubuntu 系统


在终端直接执行使用

    bash <(curl -Ls https://raw.githubusercontent.com/cxhacker1/cert/refs/heads/main/cert.sh)


下载脚本到本地目录使用

    curl -fsSL https://raw.githubusercontent.com/cxhacker1/cert/refs/heads/main/cert.sh -o cert.sh

赋予脚本执行权限
    
    chmod +x cert.sh

运行脚本
       
    ./cert.sh 


Cloudflare API token 获取请打开Cloudflare官网，在管理账户下有个账户API令牌

点击创建令牌，设置过期时间之类的，其中权限选项设置至少给到如下设置：

         Zone Read
         DNS Read
         Zone Write
         DNS Write


通常使用80端口模式申请就可以了，但是要保证系统80端口是正常开放而且没有被占用，另外要申请的域名必须已经托管解析到服务器ip


Cloudflare模式申请是通过dns鉴权的而且设置了两个模式，好处是域名只要拖管了就行，不用先解析到服务器


 单域名模式：
  
     一般常用，没有任何限制，申请的域名类型可以是一级，二级，三级什么都可以，而且不需要解析到服务器，只要托管到Cloudflare就行

 二级通配符模式：

      是给想用一个证书作用在多个a记录二级域名上，也就是一本证书可以用一级主域名也可以用在多个二级域名身上，但是出于Cloudflare限制，最多只能是二级的

      也就是 *.xxx.com，当你使用此模式申请xxx.com证书时，证书会一同添加*.xxx.com这样的二级域名支持

      申请时只要输入一级域名即可，也只能输入一级域名，不符合域名类型脚本会有错误检测