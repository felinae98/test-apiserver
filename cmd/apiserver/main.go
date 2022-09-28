package main

import (
	"log"

	testv1 "felinae98.cn/test-apiserver/pkg/apis/test/v1"
	"felinae98.cn/test-apiserver/pkg/generated/openapi"
	"sigs.k8s.io/apiserver-runtime/pkg/builder"
)

func main() {
	err := builder.APIServer.
		WithOpenAPIDefinitions("test", "v0.0.0", openapi.GetOpenAPIDefinitions).
		WithResource(&testv1.Foobar{}).
		WithLocalDebugExtension().
		WithoutEtcd().
		Execute()
	if err != nil {
		log.Fatalf("Err exec: %+v", err)
	}
}
