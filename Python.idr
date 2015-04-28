module Python

%default total

data PyTypes : Type -> Type where
  PyStr     : PyTypes String
  PyFloat   : PyTypes Float
  PyInt     : PyTypes Int
  PyInteger : PyTypes Integer
  PyChar    : PyTypes Char
  PyPtr     : PyTypes Ptr
  PyUnit    : PyTypes ()
  PyFun     : PyTypes a -> PyTypes b -> PyTypes (a -> b)

FFI_Py : FFI
FFI_Py = MkFFI PyTypes String String

-- read "pie-oh"
PIO : Type -> Type
PIO = IO' FFI_Py

infix 2 :::
record Field : Type where
  (:::) : (n : String) -> (ty : Type) -> Field

PySig : Type
PySig = List Field

data Args : Type where
  Fixed : (as : List Type) -> Args

record Object : (sig : PySig) -> Type where
  MkObject : (obj : Ptr) -> Object fs

record Method : (args : Args) -> (ret : Type) -> Type where
  MkMethod : (meth : Ptr) -> Method args ret

record Iterator : Type -> Type where
  MkIterator : (iter : Ptr) -> Iterator a

record Exception : Type where
  MkException : (ex : Ptr) -> Exception

-- Redeclare some utilities
record Yep : (x : a) -> Type where
  MkYep : x -> Yep x

data Elem : (x : a) -> List a -> Type where
  Here : Elem x (x :: xs)
  There : Elem x xs -> Elem x (y :: xs)

data HList : List Type -> Type where
  Nil : HList []
  (::) : (x : a) -> (xs : HList as) -> HList (a :: as)

%used Python.(::) x
%used Python.(::) xs

isNone : Ptr -> PIO Int
isNone p = foreign FFI_Py "idris_is_none" (Ptr -> PIO Int) p

infixl 3 /.
(/.) : Object sig -> (f : String) -> {auto pf : Elem (f ::: a) sig} -> PIO a
(/.) {a = a} (MkObject obj) f =
  believe_me <$>
    foreign FFI_Py "idris_getfield" (Ptr -> String -> PIO Ptr) obj f

infixl 3 /:
(/:) : PIO (Object sig) -> (f : String) -> {auto pf : Elem (f ::: a) sig} -> PIO a
(/:) obj f {pf = pf} = obj >>= \o => (/.) o f {pf}

methTy : Args -> Type -> Type
methTy (Fixed as) ret = HList as -> PIO ret

infixl 3 $.
($.) : Method margs ret -> methTy margs ret
($.) {margs = Fixed as} (MkMethod meth) =
  \args => believe_me <$>
    foreign FFI_Py "idris_call" (Ptr -> Ptr -> PIO Ptr) meth (believe_me args)

infixl 3 $:
($:) : PIO (Method margs ret) -> methTy margs ret
($:) {margs = Fixed as} meth = \args => meth >>= \m => m $. args

import_ : (sig : PySig) -> (modName : String) -> PIO (Object sig)
import_ sig modName =
  believe_me <$>
    foreign FFI_Py "idris_pymodule" (String -> PIO Ptr) modName

FMethod : List Type -> Type -> Type
FMethod args ret = Method (Fixed args) ret

infix 3 ~>
(~>) : List Type -> Type -> Type
(~>) args ret = FMethod args ret

foreach : (it : Iterator a) -> (st : b) -> (b -> a -> PIO b) -> PIO b
foreach (MkIterator it) st f = do
  believe_me <$>
    foreign FFI_Py "idris_foreach"
      (Ptr -> Ptr -> (Ptr -> Ptr -> Ptr) -> PIO Ptr)
      it
      (believe_me st)
      (believe_me f)

collect : (it : Iterator a) -> PIO (List a)
collect it = reverse <$> foreach it List.Nil (\xs, x => return (x :: xs))