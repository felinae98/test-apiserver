package v1

import (
	"context"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apiserver/pkg/registry/rest"
	"sigs.k8s.io/apiserver-runtime/pkg/builder/resource"
	"sigs.k8s.io/apiserver-runtime/pkg/builder/resource/resourcerest"
)

// +genclient
// +k8s:deepcopy-gen:interfaces=k8s.io/apimachinery/pkg/runtime.Object
type Foobar struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Request string `json:"request,omitempty"`
	Response string `json:"response,omitempty"`
}

func (f *Foobar) Create(ctx context.Context, obj runtime.Object, validateFunc rest.ValidateObjectFunc, options *metav1.CreateOptions) (runtime.Object, error) {
	foobarInstance := obj.(*Foobar)
	foobarInstance.Response = "Hello " + foobarInstance.Request
	return foobarInstance, nil
}

func (f *Foobar) New() runtime.Object {
	return &Foobar{}
}

func (f *Foobar) GetGroupVersionResource() schema.GroupVersionResource {
	return SchemeGroupVersion.WithResource("foobar")
}

func (f *Foobar) IsStorageVersion() bool {
	return true
}

func (f *Foobar) GetObjectMeta() *metav1.ObjectMeta {
	return &f.ObjectMeta
}

func (f *Foobar) NamespaceScoped() bool {
	return true
}

func (f *Foobar) NewList() runtime.Object {
	return &FoobarList{}
}

// +k8s:deepcopy-gen:interfaces=k8s.io/apimachinery/pkg/runtime.Object
type FoobarList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`

	Items []Foobar `json:"items"`
}

var _ resourcerest.Creator = &Foobar{}
var _ runtime.Object = &Foobar{}
var _ resource.Object = &Foobar{}

var _ runtime.Object = &FoobarList{}
