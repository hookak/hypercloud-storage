package ginkgotest

import (
	"flag"
	"fmt"
	restclient "k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	cdiclient "kubevirt.io/containerized-data-importer/pkg/client/clientset/versioned"
	"path/filepath"

	//rookclient "github.com/rook/rook/pkg/client/clientset/versioned"
	"github.com/rook/rook/pkg/util/exec"
	"k8s.io/client-go/kubernetes"
	"testing"
)

type HyperHelper struct {
	executor  *exec.CommandExecutor
	Clientset *kubernetes.Clientset
	//RookClientset    *rookclient.Clientset
	CdiClientset     *cdiclient.Clientset
	RunningInCluster bool
	T                *testing.T
}

var (
	uniqueHyperStorageHelper *HyperHelper
	uniqueConfig             *restclient.Config
)

func CreateK8sHelper(t *testing.T) (*HyperHelper, error) {
	executor := &exec.CommandExecutor{}

	var kubeconfig *string
	if home := homeDir(); home != "" {
		kubeconfig = flag.String("kubeconfig", filepath.Join(home, ".kube", "config"),
			"(optional) absolute path to the kubeconfig file")
	} else {
		kubeconfig = flag.String("kubeconfig", "", "absolute path to the kubeconfig file")
	}
	flag.Parse() // TODO flag 에 붙이는 방식때문에 **반드시** 단 한 번 이 함수가 불려야 함

	// use the current context in kubeconfig
	config, err := clientcmd.BuildConfigFromFlags("", *kubeconfig)
	if err != nil {
		panic(err.Error())
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("failed to get clientset. %+v", err)
	}

	cdiclientset, err := cdiclient.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("failed to get cdiclientset. %+v", err)
	}

	h := &HyperHelper{executor: executor, Clientset: clientset, CdiClientset: cdiclientset, T: t}

	//TODO cluster 밖에서 명령 보내는 경우 고려 (현재는 InCluster인 경우만 하고 있음)

	//if strings.Index(config.Host, "//10.") != -1 {
	//	h.RunningInCluster = true
	//}
	h.RunningInCluster = true
	uniqueHyperStorageHelper, uniqueConfig = h, config
	return h, err
}

func HyperStorageHelper() *HyperHelper {
	return uniqueHyperStorageHelper
}

func HyperStorageConfig() *restclient.Config {
	return uniqueConfig
}
