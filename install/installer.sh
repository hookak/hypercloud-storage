#!/bin/bash
set -euo pipefail
shopt -s inherit_errexit

installDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
isMinikube=false
if [ "${2:-}" = '--minikube' ]; then
  isMinikube=true
  MNT_PATH=$(minikube ssh "sudo lsblk -n -o MOUNTPOINT" | grep /mnt/ | tr -d '[\n\r]')
fi

function wait_condition {
  cond=$1
  timeout=$2

  for ((i=0; i<timeout; i+=5)) do
    echo "Waiting for ${i}s condition: \"$cond\""
    if eval $cond > /dev/null 2>&1; then echo "Conditon met"; return 0; fi;
    sleep 5
  done

  echo "Condition timeout"
  return 1
}

# helm template 이후 kubectl apply(delete)를 수행
function helm_template {
  dir=$1
  command=$2        # apply or delete

  # Minikube인 경우 Helm에 values.yaml을 그대로 넘기지 않고 설정을 바꿔서 넘김
  if $isMinikube; then
    additionalHelmSet="--set rook-ceph-core.filestorage.metaReplicas=1,rook-ceph-core.filestorage.dataReplicas=1,rook-ceph-core.filestorage.allowMultipleMdsPerNode=true,rook-ceph-core.blockstorage.replicas=1,rook-ceph-core.cephSpec.mon.count=1"
  fi

  helm template $dir -f $installDir/config.yaml ${additionalHelmSet:-} | kubectl $command -f -
}

function install {
  if $isMinikube; then
    minikube ssh "sudo mkdir -p $MNT_PATH/var/lib/rook && sudo ln -s $MNT_PATH/var/lib/rook /var/lib/rook"
  fi

  echo "========== Install hypercloud-storage-init... =========="
  helm_template $installDir/hypercloud-storage-init apply
  sleep 5

  echo "========== Install hypercloud-storage-core... =========="
  helm_template $installDir/hypercloud-storage-core apply

  echo "========== Wait install =========="
  wait_condition "kubectl get cephclusters.ceph.rook.io -n rook-ceph | grep Created" 600
  kubectl wait --for=condition=available deployment cdi-apiserver --timeout=30s -n cdi
  kubectl wait --for=condition=available deployment cdi-deployment --timeout=30s -n cdi
  kubectl wait --for=condition=available deployment cdi-operator --timeout=30s -n cdi
  kubectl wait --for=condition=available deployment cdi-uploadproxy --timeout=30s -n cdi
}

function uninstall {
  echo "========== Uninstall hypercloud-storage-core... =========="
  helm_template $installDir/hypercloud-storage-core delete

  echo "========== Wait uninstall core =========="
  wait_condition "! kubectl get cephclusters.ceph.rook.io -n rook-ceph rook-ceph" 180
  wait_condition "! kubectl get cdis.cdi.kubevirt.io -n cdi cdi" 180

  echo "========== Uninstall hypercloud-storage-init... =========="
  helm_template $installDir/hypercloud-storage-init delete

  echo "========== Wait uninstall init =========="
  wait_condition "! kubectl get ns | grep cdi" 180
  wait_condition "! kubectl get ns | grep rook-ceph" 180

  if $isMinikube; then
    minikube ssh "sudo rm -rf /var/lib/rook && sudo rm -rf $MNT_PATH/var/lib/rook"
  fi
}

function test {
  echo "TODO: go test"
}

case "${1:-}" in
install)
  install
  ;;
uninstall)
  uninstall
  ;;
test)
  test
  ;;
*)
  echo "usage:" >&2
  echo "  $0 install [--minikube]" >& 2
  echo "  $0 uninstall [--minikube]" >& 2
  echo "  $0 test" >& 2
  ;;
esac
